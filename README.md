# Building an OS
I started this project to learn more about how Operating Systems work on the lowest level, and how they interact with the filesystem and CPU.

Currently it has a minimal bootloader and kernel which just prints hello world to the screen, and it uses the FAT12 filesystem. Both the kernel and bootloader are written in assembly code. There is also a C program which implements the FAT12 read from the disk, for a slightly higher level perspective.

## Prerequisites
This project is run on a Unix-like environment and needs the following tools:

* `make`
* `nasm`              (the assembler)
* `qemu-system-x86`   (for testing the OS)
* `mtools`            (for directly accessing MS-DOS disks without mounting them)

## Build Instructions

* run `make`

## Running with qemu

* run `qemu-system-i386 -fda build/main_floppy.img`

## References
* This project was only made possible by the extremely well made tutorials by [**nanobyte**](https://www.youtube.com/@nanobyte-dev) on Youtube.
* The [**Osdev Wiki**](https://wiki.osdev.org/Expanded_Main_Page) also helped alot, especially with the FAT12 specifications.
