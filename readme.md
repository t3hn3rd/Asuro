# Asuro

We welcome everyone to give building/breaking/fixing/shooting Asuro a go, feel free to follow the steps below and mess with Asuro for fun or profit.

## Setting up your build environment

### Prerequisites
* [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
    WSL2 is used in conjunction with Docker to predefine a build environment for Asuro.
* [Docker for Windows](https://docs.docker.com/docker-for-windows/install/)
    Docker is used to ensure a predefined environment with the correct versions of; Freepascal, Binutils, NASM, Make, xorriso & grub-mk-rescue installed is used for compilation. An ISO will be generated at the end of the build process.
* [Git (Obviously)](https://git-scm.com/)
    I don't think this needs an explaination.
* [VSCode (Optional, but highly recommended)](https://code.visualstudio.com/)
    Visual Studio code is our IDE of choice, and we have a number of recommended plugins.
    * [PowerShell Plugin by Microsoft](https://marketplace.visualstudio.com/items?itemName=ms-vscode.powershell)
        This plugin gives you the ability to use the 'PowerShell' task type, allowing the automatic launching of virtualbox with the resulting image generated during compilation of Asuro.
* [VirtualBox](https://www.virtualbox.org/)
    Virtualbox is our Virtualisation environment of choice, don't ask why, it just is.

### Installation (correct as of 2021/06/20)
1. Install WSL2 as described in the article linked above & ensure Virtualization is enabled in the BIOS.
2. Ensure WSL2 is used by default with the following command:
    ```powershell
    wsl --set-default-version 2
    ```
3. Install Docker for Windows.
4. Install Git for Windows.
5. Install VSCode & the listed plugins.
6. Install VirtualBox (v7+).
7. Clone this repository.
8. Run the following command in the root of the repo to build the docker image:
    ```powershell
    docker compose build builder
    ```
9. Run the following command to compile Asuro:
    ```powershell
    docker compose run builder
    ```
10. Create a new virtual machine in Virtualbox and mount the `Asuro.iso` generated in step 9 as a boot image.
11. Add the virtualbox installation directory to your `%PATH%` environment variable, usually:
    ```
    %PROGRAMFILES%\Oracle\VirtualBox
    ```
12. Naviage to your virtualbox machines folder, this is usually the following
    ```
    %userprofile%\VirtualBox VMs\<VM Name>
    ```
    Open the Virtual Machine Definition file (.vbox) in your text editor of choice and find the following line:
    ```xml
    <Machine uuid="{7d395c96-891c-4139-b77d-9b6b144b0b93}" name="Asuro" OSType="Linux" snapshotFolder="Snapshots" lastStateChange="2021-06-20T20:33:07Z">
    ```
    Copy the uuid, in our case `7d395c96-891c-4139-b77d-9b6b144b0b93` and replace the uuid found in `.vscode\launch.json` under `args`, so that it looks something like this:
    ```json
    {
        "configurations": [
            {
                "name":"Run",
                "request": "launch",
                "type": "PowerShell",
                "preLaunchTask": "Build",
                "script": "${workspaceFolder}/virtualbox-wrapper.ps1",
                "args": ["-MachineName", "7d395c96-891c-4139-b77d-9b6b144b0b93"],
                "cwd": "${workspaceFolder}",
            }
        ]
    }
    ```
    This will allow VSCode to automatically launch VirtualBox once Asuro has been compiled.
13. Open your project folder in VSCode, use CTRL+SHIFT+B to build & F5 to build + run in VBox.
14. Congratulations! You can now play with Asuro!

### Notes & Gotchas
- The above process has been updated to be compatible with VirtualBox 7+, in which VBoxSDL was removed and vboxmanage should be used in its place. A small wrapper powershell script is used to achieve this.
- It was noted that Windows builds above `20H2` seem to have issues installing WSL2. We may have to wait for a patch from Microsoft to fix this. Our devs are currently using build `20H2`.
