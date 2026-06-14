# maifetch
a really lazy fetch tool for [maitea](https://maitea.app) written in Delphi-compatible Object Pascal.

![image](https://github.com/user-attachments/assets/96cd7018-8a00-4785-a1a8-9fe503263662)

## configuration
| variable     | description                                        | default                                    | environment variable | cli argument          |
|--------------|----------------------------------------------------|--------------------------------------------|----------------------|-----------------------|
| access token | token for your MaiTea account (REQUIRED)           | `N/A`                                      | `MAITEA_TOKEN`       | `--access-token` `-a` |
| logo size    | size of the ASCII logo (zero or negative disables) | `20`                                       | `MAITEA_LOGO_SIZE`   | `--logo-size` `-l`    |
| score count  | amount of scores to display (max 12)               | `4`                                        | `MAITEA_SCORE_COUNT`  | `--score-count` `-s`  |
| config file  | json file to store config variables                | [refer to below](#default-config-location) | `MAITEA_CONFIG_FILE` | `--config-file` `-c`  |

### Default config location
obtained from `os.UserConfigDir` 

| platform | location                                                    |
|----------|-------------------------------------------------------------|
| Windows  | `%APPDATA%/maifetch.json`                                   |
| Linux    | `$XDG_CONFIG_HOME/maifetch.json`  `~/.config/maifetch.json` |
| OSX      | `~/Library/Application Support/maifetch.json`               |

## how to build
1. clone the project with `git clone https://github.com/HutchyBen/maifetch`
2. install Free Pascal 3.2+ (`brew install fpc` on macOS or the distro `fpc` packages on Linux)
3. build with `fpc -Mdelphi -FEbuild -FUbuild src/maifetch.pas`
4. run `build/maifetch`, ensuring access token is either
    - in config file
    - in environment variables
    - in command line options

## validation
Run the fixture test without a MaiTea token:

```sh
./test/run-fixture.sh
```

The fixture test compiles the Delphi-mode Pascal source with Free Pascal and verifies profile and recent-score rendering from local JSON fixtures.


## todo
- test it properly
- add friendly errors
