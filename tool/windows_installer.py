import argparse
from pathlib import Path
import re
import subprocess

from jinja2 import Environment, StrictUndefined


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('version')
    parser.add_argument('source')
    parser.add_argument('output')
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+', args.version):
        raise ValueError('Invalid installer version')
    root = Path(__file__).resolve().parents[1]
    source = Path(args.source).resolve(strict=True)
    if not (source / 'FlClash.exe').is_file():
        raise ValueError('Missing application bundle')
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    template = root / 'windows/packaging/exe/inno_setup.iss'
    script = Environment(undefined=StrictUndefined).from_string(
        template.read_text(encoding='utf-8')).render(
        APP_ID='728B3532-C74B-4870-9068-BE70FE12A3E6',
        APP_VERSION=args.version,
        APP_NAME='FlClash', DISPLAY_NAME='FlClash',
        PUBLISHER_NAME='ZhuoMneg',
        PUBLISHER_URL='https://github.com/ZhuoMneg/FlClash',
        INSTALL_DIR_NAME=r'{autopf}\FlClash',
        OUTPUT_BASE_FILENAME=f'FlClash-{args.version}-windows-amd64-setup',
        SETUP_ICON_FILE=str(root / 'windows/runner/resources/app_icon.ico'),
        PRIVILEGES_REQUIRED='admin', ARCH='x64compatible',
        EXECUTABLE_NAME='FlClash.exe', SOURCE_DIR=str(source),
        CHINESE_SIMPLIFIED_MESSAGES=str(
            root / 'windows/packaging/exe/ChineseSimplified.isl'),
        CREATE_DESKTOP_ICON=False,
        LOCALES=[dict(lang='en', file=''), dict(
            lang='zh', file='"' + str(root / 'windows/packaging/exe/ChineseSimplified.isl') + '"')],
    )
    script_path = output / 'FlClash.iss'
    script_path.write_text(script, encoding='utf-8-sig')
    subprocess.run([args.compiler, str(script_path)], cwd=output, check=True)
    package = output / f'FlClash-{args.version}-windows-amd64-setup.exe'
    if not package.is_file() or package.stat().st_size == 0:
        raise ValueError('Missing installer output')


if __name__ == '__main__':
    main()
