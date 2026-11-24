# Asuro

We welcome everyone to give building/breaking/fixing/shooting Asuro a go, feel free to follow the steps below and mess with Asuro for fun or profit.

See the [x86-64 port guide](doc/planning/x86_64.md) for native target status.

## Getting Started

Install Docker with Compose and Git, then clone this repository. From the repository root, build the image and the bootable ISO.

```sh
docker compose build builder
docker compose run --rm builder iso
```

Attach the generated root-level `Asuro.iso` as optical media in a BIOS-based VM. See the [build command reference](doc/index.md#getting-started) for test profiles, kernel-only builds and documentation. The [build pipeline](doc/toolchain/compile.md) explains the PowerShell and Ninja setup.

### Optional VirtualBox integration

Install VirtualBox and, if using VS Code, the PowerShell extension.

1. Add the virtualbox installation directory to your `%PATH%` environment variable, usually:
    ```
    %PROGRAMFILES%\Oracle\VirtualBox
    ```
2. Navigate to your virtualbox machines folder, this is usually the following
    ```
    %userprofile%\VirtualBox VMs\<VM Name>
    ```
    Open the Virtual Machine Definition file (.vbox) in your text editor of choice and find the following line:
    ```xml
    <Machine uuid="{7d395c96-891c-4139-b77d-9b6b144b0b93}" name="Asuro" OSType="Linux" snapshotFolder="Snapshots" lastStateChange="2021-06-20T20:33:07Z">
    ```
    Copy the uuid, in our case `7d395c96-891c-4139-b77d-9b6b144b0b93` & create a `localenv.json` file in the project root with the following content:
    ```json
    {
        "VirtualBox":{
            "MachineName":"<YOUR_UUID_OR_MACHINE_NAME>"
        }
    }
    ```
    This will allow VSCode to automatically launch VirtualBox once Asuro has been compiled.
    
    You can also enable the serial adapter "COM1" in mode "Raw File", give it a path, and provide this path in the `localenv.json` as follows:
    ```json
    {
        "VirtualBox" : {
            "MachineName": "<YOUR_UUID_OR_MACHINE_NAME>",
            "LogLocation": "Fully\\Qualified\\Path\\To\\Your\\Log\\File"
        }
    }
    ```
    This will allow you to see the console output from Asuro in your host terminal.
3. Open your project folder in VSCode, use CTRL+SHIFT+B to build & F5 to build + run in VBox.
