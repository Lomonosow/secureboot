# secureboot
## Usage
```
Usage: secureboot [action] [options]
Manage secureboot

Actions:
  --init                     This action will generate secureboot keys
  -s, --sign [file]          Sign file with ISK key
                                 signed file will be located in the same directory that source file
                                 and have postfix '.signed'. Can be overwrited by --output option
  --enroll-keys              Enroll keys into UEFI when system in Setup Mode
  --is-setup                 Check is system in Setup Mode

Options:
  --no-color                 Disable colorizing
  --verbose                  Enable more verbose output
  --secure-db                Generate ISK key encrypted. You will enter passphrase when signing images.
  --no-pass                  Generate keys unencrypted. [NOT RECOMMENDED]
  --key-size                 Generate keys of specified length. Default: 2048
  --output                   Write signed data to file
  -h, --help                 Show this help message and exit
  -v, --version              Show program version
```
