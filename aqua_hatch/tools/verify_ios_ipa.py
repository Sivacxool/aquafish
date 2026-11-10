"""Check a device IPA without needing signing credentials or Apple tooling."""
from pathlib import Path
import hashlib,json,plistlib,struct,sys,zipfile

path=Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None, 'Corrupt IPA archive'
    info=plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
    assert info['CFBundleIdentifier']=='th.ac.aquahatch.aquaHatch'
    assert info['CFBundleShortVersionString']=='0.18.0'
    assert info['NSLocalNetworkUsageDescription']
    assert info['NSAppTransportSecurity']['NSAllowsLocalNetworking'] is True
    assert not info['NSAppTransportSecurity'].get('NSAllowsArbitraryLoads',False)
    executable=archive.read('Payload/Runner.app/'+info['CFBundleExecutable'])
    magic,cpu=struct.unpack_from('<II',executable)
    assert magic==0xfeedfacf and cpu==0x0100000c, 'Expected an arm64 Mach-O device binary'
    assert any(n.endswith('/flutter_assets/FontManifest.json') for n in archive.namelist())
    assert any(n.endswith('/flutter_assets/assets/device/device_ca.pem') for n in archive.namelist())
    assert any(n.endswith('/flutter_assets/assets/device/camera_ca.pem') for n in archive.namelist())
    assert any(n.endswith('/flutter_assets/assets/models/fishfry_heads_v1.onnx') for n in archive.namelist())
    names=archive.namelist()
    report={'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
            'bundle_id':info['CFBundleIdentifier'],'minimum_ios':info.get('MinimumOSVersion'),
            'architecture':'arm64','supported_platforms':info.get('CFBundleSupportedPlatforms'),
            'local_network_description_present':True,'arbitrary_transport_loads_allowed':False,
            'device_and_camera_ca_included':True,'archive_files':len(names),
            'signing_status':'Unsigned build; must be signed with the owner Apple account before installation.',
            'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    assert info.get('CFBundleSupportedPlatforms')==['iPhoneOS'], 'Not a physical iOS device build'
dest=path.parent/'ipa-verification.json'
dest.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False))
