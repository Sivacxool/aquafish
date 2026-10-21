"""Reject APKs that advertise ABIs without a complete Flutter runtime."""
import argparse
import sys
import zipfile


def validate(path, expected=None):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        abis = sorted({n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')})
        if not abis:
            raise ValueError('APK has no native libraries')
        if expected and set(abis) != set(expected):
            raise ValueError(f'Expected ABIs {sorted(expected)}, found {abis}')
        missing = [f'lib/{abi}/{lib}' for abi in abis for lib in ('libflutter.so', 'libapp.so')
                   if f'lib/{abi}/{lib}' not in names]
        if missing:
            raise ValueError('Incomplete Flutter ABI: ' + ', '.join(missing))
        if archive.testzip() is not None:
            raise ValueError('APK ZIP integrity check failed')
        return abis


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument('--expected', nargs='+')
    args = parser.parse_args()
    try:
        print('PASS: complete Flutter libraries for ' + ', '.join(validate(args.apk, args.expected)))
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
