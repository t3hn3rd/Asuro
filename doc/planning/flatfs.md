#Flat filesystem

A super simple filesystem for asuro. Folders are emulated in filenames.

Starts with disk info sector, sector 0 of volume

---
#### disk info

jmp2boot        : ubit24;
OEMName         : array[0..7] of char;
version         : uint16 // numerical version of filesystem
sectorCount      : uint16;
fileCount       : uint16
signature       : uint32 = 0x0B00B1E5


the Rest of the sector is reserved

---

Starting from sector 1 is the file table. Table size is determined by entry size (64) * fileCount

---
####File entry

name : array[0..59] of char //file name max 60 chars
fileStart : 16bit // start sector of data
fileSize : 16bit // data size in sectors

---

