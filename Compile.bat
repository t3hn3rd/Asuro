@echo off
set /a ERRCOUNT=0
echo =======================
echo == ASURO COMPILATION ==
echo =======================
echo.
echo Compiling ASM Stub...
echo.
nasm -f elf src\stub.asm -o lib\stub.o
if %ERRORLEVEL% GEQ 1 (
	echo Failed to compile stub!
	set /a ERRCOUNT=%ERRCOUNT%+1
) ELSE (
	echo Success.
)
echo.
echo =======================
echo.
echo Compiling FPC Sources...
echo.
fpc -Aelf -n -O3 -Op3 -Si -Sc -Sg -Xd -CX -XXs -Rintel -Tlinux -FElib\ src\kernel.pas
if %ERRORLEVEL% GEQ 1 (
	echo Failed to compile FPC Sources!
	set /a ERRCOUNT=%ERRCOUNT%+1
) ELSE (
	echo Success.
)
echo.
echo =======================
echo.
echo Linking...
echo.
ld -A elf32-i386 --gc-sections -s -Tlinker.script -o bin\kernel.obj lib\stub.o lib\kernel.o lib\multiboot.o lib\system.o lib\console.o
if %ERRORLEVEL% GEQ 1 (
	echo Failed linking!
	set /a ERRCOUNT=%ERRCOUNT%+1
) ELSE (
	echo Success.
)
echo.
echo =======================
echo.
if %ERRCOUNT% GEQ 1 (
	echo %ERRCOUNT% Errors Occurred, please review.
) ELSE (
	echo No errors. 
)
echo.
echo =======================
echo.
echo Press any key to exit...
pause > nul