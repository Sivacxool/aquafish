import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';

const root = 'http://127.0.0.1:8789';
const digest = data => createHash('sha256').update(data).digest('hex');
function keys(token) {
  const writer = digest('aquahatch relay write v1:' + token);
  const reader = digest('aquahatch relay read v1:' + writer);
  return { writer, reader, room: digest('aquahatch relay room v1:' + reader) };
}

async function send(method, path, key, body, expected, headers = {}) {
  const response = await fetch(root + path, {
    method,
    headers: { Authorization: 'Bearer ' + key, ...headers },
    body: body instanceof Uint8Array ? body : body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status, expected, method + ' ' + path.replace(/[0-9a-f]{64}/g, '[room]'));
  return response;
}

const board = keys('1'.repeat(64));
const camera = keys('2'.repeat(64));
const notAllowed = keys('3'.repeat(64));
const readingPath = '/v1/readings/' + board.room;
const camPath = '/v1/cameras/' + camera.room;
const now = new Date().toISOString();

await send('GET', '/v1/readings/' + notAllowed.room, notAllowed.reader, undefined, 401);
await send('GET', readingPath, board.writer, undefined, 401);
await send('POST', readingPath, board.reader, {}, 401);
const snapshot = {
  backend: 'esp32-local', device_id: 's3-aabbccddee01', protocol_version: 1,
  telemetry: { timestamp: now, device_online: true, simulated: false, temperature_c: 28.5 },
};
await send('POST', readingPath, board.writer, snapshot, 200);
const reading = await (await send('GET', readingPath, board.reader, undefined, 200)).json();
assert.deepEqual(reading.snapshot, snapshot);
assert.ok(reading.age_ms < 45000);

const cameraState = {
  backend: 'esp32-camera', device_id: 'cam-aabbccddee02', camera_id: 'cam-aabbccddee02',
  protocol_version: 1, configured: true, online: true, sensor: 'OV3660',
};
const waiting = await (await send('POST', camPath + '/agent', camera.writer, cameraState, 200)).json();
assert.equal(waiting.job, null);
await send('GET', camPath + '/camera', camera.reader, undefined, 200);

const id = randomUUID();
const options = {
  capture_id: id, resolution: '3mp', autofocus: false, flash: true,
  flash_duty: 64, warmup_ms: 1800, jpeg_quality: 10,
};
const captured = camPath + '/camera/captures/' + id;
const enqueued = await (await send('POST', camPath + '/camera/captures', camera.reader, options, 202)).json();
assert.equal(enqueued.status, 'queued');
const work = await (await send('POST', camPath + '/agent', camera.writer, cameraState, 200)).json();
assert.equal(work.job.capture_id, id);
assert.ok(work.job.expires_at_unix > Date.now() / 1000);
const duplicate = await (await send('POST', camPath + '/agent', camera.writer, cameraState, 200)).json();
assert.equal(duplicate.job, null);
await send('GET', captured + '/image', camera.reader, undefined, 409);

// Synthetic marker bytes exercise transport integrity without using a user's photo.
const image = Uint8Array.from([255, 216, 17, 21, 255, 217]);
const metadata = {
  ...cameraState, capture_id: id, status: 'captured', bytes: image.length,
  sha256: digest(image), received_at: now, width: 2048, height: 1536,
};
await send('POST', camPath + '/agent/photo/' + id, camera.reader, image, 401);
await send('POST', camPath + '/agent/photo/' + id, camera.writer, image, 422, {
  'X-AquaHatch-Photo': JSON.stringify({ ...metadata, sha256: '0'.repeat(64) }),
});
await send('POST', camPath + '/agent/photo/' + id, camera.writer, image, 200, {
  'X-AquaHatch-Photo': JSON.stringify(metadata),
});
const done = await (await send('GET', captured, camera.reader, undefined, 200)).json();
assert.equal(done.status, 'captured');
const photo = await send('GET', captured + '/image', camera.reader, undefined, 200);
assert.equal(photo.headers.get('content-type'), 'image/jpeg');
assert.equal(photo.headers.get('cache-control'), 'no-store');
assert.deepEqual(new Uint8Array(await photo.arrayBuffer()), image);
await send('POST', readingPath + '/access', board.reader, { enabled: false }, 401);
await send('POST', readingPath + '/access', board.writer, { enabled: 'false' }, 422);
const disabled = await send('POST', readingPath + '/access', board.writer, { enabled: false }, 200);
assert.deepEqual(await disabled.json(), { enabled: false });
await send('POST', readingPath + '/access', board.writer, { enabled: false }, 200);
await send('GET', readingPath, board.reader, undefined, 423);
await send('POST', readingPath, board.writer, snapshot, 423);
await send('GET', captured + '/image', camera.reader, undefined, 200);
await send('POST', readingPath + '/access', board.writer, { enabled: true }, 200);
await send('GET', readingPath, board.reader, undefined, 404);
await send('POST', readingPath, board.writer, snapshot, 200);

await send('POST', camPath + '/access', camera.writer, { enabled: false }, 200);
await send('GET', captured + '/image', camera.reader, undefined, 423);
await send('POST', camPath + '/agent', camera.writer, cameraState, 423);
await send('POST', camPath + '/camera/captures', camera.reader, options, 423);
await send('GET', readingPath, board.reader, undefined, 200);
await send('POST', camPath + '/access', camera.writer, { enabled: true }, 200);
await send('GET', captured + '/image', camera.reader, undefined, 410);

const pending = { ...options, capture_id: randomUUID() };
await send('POST', camPath + '/agent', camera.writer, cameraState, 200);
await send('POST', camPath + '/camera/captures', camera.reader, pending, 202);
await send('POST', camPath + '/access', camera.writer, { enabled: false }, 200);
await send('POST', camPath + '/access', camera.writer, { enabled: true }, 200);
const afterEnable = await send('POST', camPath + '/agent', camera.writer, cameraState, 200);
assert.equal((await afterEnable.json()).job, null);
console.log('PASS: relay off/on, writer-only settings, room isolation, and discarded data and capture jobs');
