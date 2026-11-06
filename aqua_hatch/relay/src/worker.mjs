import { DurableObject } from 'cloudflare:workers';

const MAX_AGE_MS = 45_000;
const MAX_PHOTO_BYTES = 1_500_000;
const encoder = new TextEncoder();
const keyFormat = /^[0-9a-f]{64}$/;
const captureIdFormat = /^[a-zA-Z0-9_-]{1,64}$/;

async function digest(bytes) {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(hash, byte => byte.toString(16).padStart(2, '0')).join('');
}

function hash(label, value) {
  return digest(encoder.encode(label + value));
}

function equal(left, right) {
  return crypto.subtle.timingSafeEqual(encoder.encode(left), encoder.encode(right));
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method;
    if (url.pathname === '/health' && method === 'GET') {
      return json({ service: 'aquahatch-relay', protocol: 1 });
    }

    const match = /^\/v1\/(readings|cameras)\/([0-9a-f]{64})(\/.*)?$/.exec(url.pathname);
    if (!match || url.search) return json({ error: 'not_found' }, 404);
    const [, kind, room, suffix = ''] = match;
    const agent = /^\/agent(?:\/(?:photo|error)\/[a-zA-Z0-9_-]{1,64})?$/.test(suffix);
    const camera = /^\/camera(?:\/captures(?:\/[a-zA-Z0-9_-]{1,64}(?:\/image)?)?)?$/.test(suffix);
    const access = suffix === '/access' && ['GET', 'POST'].includes(method);
    const valid = access || (kind === 'readings'
      ? !suffix && ['GET', 'POST'].includes(method)
      : (agent && method === 'POST') ||
        (camera && (method === 'GET' || (method === 'POST' && suffix === '/camera/captures'))));
    if (!valid) return json({ error: 'not_found' }, 404);

    const authorization = request.headers.get('Authorization') ?? '';
    const key = authorization.slice(7);
    const namespace = kind + ':' + room;
    if (!authorization.startsWith('Bearer ') || !keyFormat.test(key) ||
        !env.RELAY_ROOMS?.split(/[\s,]+/).includes(namespace)) {
      return json({ error: 'unauthorized' }, 401);
    }
    const writing = access || (kind === 'readings' ? method === 'POST' : agent);
    const reader = writing ? await hash('aquahatch relay read v1:', key) : key;
    if (!equal(room, await hash('aquahatch relay room v1:', reader))) {
      return json({ error: 'unauthorized' }, 401);
    }

    const stub = env.READINGS.get(env.READINGS.idFromName(namespace));
    const headers = new Headers();
    const metadata = request.headers.get('X-AquaHatch-Photo');
    if (metadata && metadata.length <= 2048) headers.set('X-AquaHatch-Photo', metadata);
    // The credential is checked above and stays out of the durable storage.
    return stub.fetch(new Request('https://room.internal' + (suffix || '/readings'), {
      method,
      headers,
      body: method === 'POST' ? request.body : undefined,
    }));
  },
};

async function boundedBody(request, max) {
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > max) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  } catch {
    return null;
  }
}

async function object(request) {
  const bytes = await boundedBody(request, 8192);
  try {
    const data = bytes ? JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) : null;
    return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
  } catch {
    return null;
  }
}

function cameraIdentity(camera) {
  return {
    backend: 'esp32-camera',
    protocol_version: 1,
    device_id: camera.device_id,
    camera_id: camera.device_id,
    server_time_unix: Math.floor(Date.now() / 1000),
  };
}

function validCamera(camera) {
  return camera?.backend === 'esp32-camera' && camera.protocol_version === 1 &&
    /^cam-[0-9a-f]{12}$/.test(camera.device_id) && camera.camera_id === camera.device_id;
}

function validOptions(data) {
  return data && captureIdFormat.test(data.capture_id) &&
    typeof data.capture_id === 'string' &&
    ['sensor_max', '5mp', '3mp', 'uxga', 'svga'].includes(data.resolution) &&
    [data.flash, data.autofocus].every(value => typeof value === 'boolean') &&
    Number.isInteger(data.warmup_ms) && data.warmup_ms >= 0 && data.warmup_ms <= 3000 &&
    Number.isInteger(data.flash_duty) && data.flash_duty >= 16 && data.flash_duty <= 96 &&
    Number.isInteger(data.jpeg_quality) && data.jpeg_quality >= 4 && data.jpeg_quality <= 16;
}

function active(value, now = Date.now()) {
  return value && value.expires > now ? value : null;
}

function remoteDisabled() {
  return json({ error: 'remote_disabled', detail: 'ปิดการดูจากนอกบ้านไว้' }, 423);
}

export class ReadingRoom extends DurableObject {
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === '/access') return this.access(request);
    const access = await this.ctx.storage.get('access');
    if (access?.enabled === false) return remoteDisabled();
    const revision = access?.revision ?? 0;
    if (path === '/readings') return this.readings(request, revision);
    if (path === '/agent') return this.heartbeat(request, revision);
    if (path.startsWith('/agent/')) return this.finishCapture(request, path, revision);
    return this.camera(request, path, revision);
  }

  async access(request) {
    const storage = this.ctx.storage;
    if (request.method === 'GET') {
      return json({ enabled: (await storage.get('access'))?.enabled !== false });
    }
    const input = await object(request);
    if (typeof input?.enabled !== 'boolean') {
      return json({ error: 'invalid_access_state' }, 422);
    }
    return storage.transaction(async txn => {
      const previous = await txn.get('access');
      if (input.enabled !== (previous?.enabled !== false)) {
        await txn.put('access', { enabled: input.enabled, revision: (previous?.revision ?? 0) + 1 });
        if (!input.enabled) {
          await txn.delete(['latest', 'camera', 'job', 'photo']);
        }
      }
      return json({ enabled: input.enabled });
    });
  }

  async stillOpen(revision) {
    // Recheck after network body reads/digests. A request in flight during
    // disable and re-enable cannot recreate an old reading or capture.
    const access = await this.ctx.storage.get('access');
    return access?.enabled !== false && (access?.revision ?? 0) === revision;
  }

  async readings(request, revision) {
    const storage = this.ctx.storage;
    if (request.method === 'POST') {
      const data = await object(request);
      if (data?.backend !== 'esp32-local' || data.protocol_version !== 1 ||
          !/^s3-[0-9a-f]{12}$/.test(data.device_id) ||
          data.telemetry?.simulated !== false || data.telemetry.device_online !== true ||
          !Number.isFinite(Date.parse(data.telemetry.timestamp))) {
        return json({ error: 'invalid_snapshot' }, 422);
      }
      if (!await this.stillOpen(revision)) return remoteDisabled();
      const now = Date.now();
      const previous = await storage.get('latest');
      if (previous && now - previous.at < 3000) return json({ error: 'try_later' }, 429);
      await storage.put('latest', { at: now, expires: now + MAX_AGE_MS, data });
      await storage.setAlarm(now + MAX_AGE_MS);
      return json({ accepted: true });
    }
    const latest = active(await storage.get('latest'));
    if (!latest) return json({ error: 'board_unavailable' }, 404);
    return json({ age_ms: Math.max(0, Date.now() - latest.at), snapshot: latest.data });
  }

  async heartbeat(request, revision) {
    const camera = await object(request);
    if (!validCamera(camera)) return json({ error: 'invalid_camera' }, 422);
    if (!await this.stillOpen(revision)) return remoteDisabled();
    const storage = this.ctx.storage;
    const now = Date.now();
    const status = { expires: now + 24_000, data: camera };
    const job = active(await storage.get('job'), now);
    if (!job || job.status !== 'queued') {
      await storage.put('camera', status);
      return json({ job: null });
    }
    job.status = 'capturing';
    await storage.put({ camera: status, job });
    return json({ job: job.options });
  }

  async camera(request, path, revision) {
    let options;
    if (request.method === 'POST') {
      options = await object(request);
      if (!validOptions(options)) return json({ detail: 'ตรวจค่าการถ่ายภาพ' }, 422);
      if (!await this.stillOpen(revision)) return remoteDisabled();
    }
    const storage = this.ctx.storage;
    const camera = active(await storage.get('camera'));
    const job = active(await storage.get('job'));
    if (path === '/camera') {
      if (!camera) return json({ error: 'camera_unavailable' }, 404);
      return json({ ...camera.data, ...cameraIdentity(camera.data) });
    }
    if (options) {
      const current = job;
      if (current?.options.capture_id === options.capture_id) {
        return json(current.result ?? { ...current.identity, capture_id: options.capture_id, status: current.status }, 202);
      }
      if (!camera?.data.online || !camera.data.configured) {
        return json({ detail: 'กล้องยังไม่พร้อมผ่านอินเทอร์เน็ต' }, 503);
      }
      if (current && ['queued', 'capturing'].includes(current.status)) {
        return json({ detail: 'กล้องกำลังถ่ายภาพ' }, 409);
      }
      const expires = Date.now() + 45_000;
      const identity = cameraIdentity(camera.data);
      await storage.delete('photo');
      await storage.put('job', {
        expires,
        identity,
        status: 'queued',
        options: { ...options, expires_at_unix: Math.floor(expires / 1000) },
      });
      await storage.setAlarm(expires);
      return json({ ...identity, capture_id: options.capture_id, status: 'queued' }, 202);
    }
    const id = path.split('/')[3];
    if (!job || id !== job.options.capture_id) return json({ detail: 'ภาพหมดอายุแล้ว' }, 410);
    if (path.endsWith('/image')) {
      if (job.status !== 'captured') return json({ detail: 'ภาพยังไม่พร้อม' }, 409);
      const bytes = await storage.get('photo');
      if (!bytes) return json({ detail: 'ภาพหมดอายุแล้ว' }, 410);
      return new Response(bytes, {
        headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'no-store', 'X-Capture-ID': id },
      });
    }
    return json(job.result ?? { ...job.identity, capture_id: id, status: job.status });
  }

  async finishCapture(request, path, revision) {
    const [, , action, id] = path.split('/');
    const storage = this.ctx.storage;
    if (action === 'error') {
      const job = active(await storage.get('job'));
      if (!job || job.options.capture_id !== id || job.status !== 'capturing') {
        return json({ error: 'capture_expired' }, 410);
      }
      job.status = 'failed';
      await storage.put('job', job);
      return json({ accepted: true });
    }

    const bytes = await boundedBody(request, MAX_PHOTO_BYTES);
    let metadata;
    try {
      metadata = JSON.parse(request.headers.get('X-AquaHatch-Photo') ?? '');
    } catch {
      return json({ error: 'invalid_photo' }, 422);
    }
    if (!bytes || bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 ||
        bytes.at(-2) !== 255 || bytes.at(-1) !== 217 || metadata?.bytes !== bytes.length ||
        metadata.capture_id !== id || metadata.status !== 'captured' ||
        !keyFormat.test(metadata.sha256) || metadata.sha256 !== await digest(bytes)) {
      return json({ error: 'invalid_photo' }, 422);
    }
    if (!await this.stillOpen(revision)) return remoteDisabled();
    const job = active(await storage.get('job'));
    if (!job || job.options.capture_id !== id || job.status !== 'capturing' ||
        metadata.device_id !== job.identity.device_id || !validCamera(metadata)) {
      return json({ error: 'capture_expired' }, 410);
    }
    job.result = metadata;
    job.status = 'captured';
    job.expires = Date.now() + 60_000;
    await storage.put({ job, photo: bytes });
    await storage.setAlarm(job.expires);
    return json({ accepted: true });
  }

  async alarm() {
    const storage = this.ctx.storage;
    const latest = await storage.get('latest');
    const job = await storage.get('job');
    if (latest && !active(latest)) await storage.delete('latest');
    if (job && !active(job)) await storage.delete(['job', 'photo']);
    const remaining = active(latest) ?? active(job);
    if (remaining) await storage.setAlarm(remaining.expires);
  }
}
