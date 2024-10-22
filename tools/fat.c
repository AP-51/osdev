#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef uint8_t bool; //defining the bool type
#define true 1
#define false 0

typedef struct
{
	//referenced from the FAT12 section of osdev wiki
	uint8_t BootJumpInstruction[3];
	uint8_t OemIdentifier[8];
	uint16_t BytesPerSector;
	uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

	//extended boot record
	uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;          // serial number, value doesn't matter
    uint8_t VolumeLabel[11];    // 11 bytes, padded with spaces
    uint8_t SystemId[8];

	// Only the FAT headers, no bootloader code here
} __attribute__((packed))BootSectorStruct;  //attribute is added so that compiler doesn't move around bytes for optimization

typedef struct{

	// Directory Entry as per FAT12 specification
	uint8_t Name[11];
	uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t size;
}__attribute__((packed)) DirectoryEntry;


BootSectorStruct BootSector;
uint8_t* Fat = NULL;
DirectoryEntry* RootDirectory = NULL;
uint32_t RootDirectoryEnd;

bool readBootSector(FILE* disk){

	return fread(&BootSector,sizeof(BootSector),1,disk)>0;
	// if(fread(&BootSector, sizeof(BootSector),1,disk)>0){
	// 	printf("Read Successful\n");
	// 	return true;
	// }
	// else return false;
}
bool readSectors(FILE* disk,uint32_t lba, uint32_t count, void* bufferOut){

	bool check = true;
	check = check && (fseek(disk,lba*BootSector.BytesPerSector,SEEK_SET)==0);
	check = check && (fread(bufferOut,BootSector.BytesPerSector,count,disk)==count); //fread returns the number of items it has read which should be count
	return check;
}

bool readFat(FILE* disk){
	
	Fat = (uint8_t*) malloc(BootSector.SectorsPerFat * BootSector.BytesPerSector);
	return readSectors(disk, BootSector.ReservedSectors, BootSector.SectorsPerFat, Fat);


}

bool readRootDirectory(FILE* disk){

	uint32_t lba = BootSector.ReservedSectors + BootSector.SectorsPerFat*BootSector.FatCount;
	uint32_t size = sizeof(DirectoryEntry)*BootSector.DirEntryCount;
	uint32_t sectors = (size/BootSector.BytesPerSector);
	if(size%BootSector.BytesPerSector>0) sectors++;
	RootDirectoryEnd = lba+sectors;
	RootDirectory = (DirectoryEntry*)malloc(sectors*BootSector.BytesPerSector);
	return readSectors(disk,lba,sectors,RootDirectory);
}

DirectoryEntry* findFile(const char* name){

	for(uint32_t i = 0;i<BootSector.DirEntryCount;i++){
		if(memcmp(name,RootDirectory[i].Name,11)== 0) return &RootDirectory[i];
	}
	return NULL;
}

bool readFile(DirectoryEntry* fileEntry,FILE* disk,uint8_t* outputBuffer){
	
	bool check = true;
	uint16_t currentCluster = fileEntry->FirstClusterLow;

	do{
		uint32_t lba = RootDirectoryEnd + (currentCluster - 2)*BootSector.SectorsPerCluster;
		check = check && readSectors(disk,lba,BootSector.SectorsPerCluster,outputBuffer);
		outputBuffer += BootSector.SectorsPerCluster*BootSector.BytesPerSector;

		uint32_t fatIndex = currentCluster*3/2;
		if(currentCluster%2==0) currentCluster = (*(uint16_t*)(Fat+fatIndex)) & 0x0FFF;
		else currentCluster = (*(uint16_t*)(Fat+fatIndex)) >> 4;
	} while (check && currentCluster < 0x0FF8);

	return check;
}

int main(int argc, char* argv[]){
	if(argc<3){
		printf("Usage: %s <disk image> <file name>\n",argv[0]);
		return -1;
	}

	FILE* disk = fopen(argv[1],"rb");
	if(!disk){
		fprintf(stderr, "Error opening Disk Image: %s!\n",argv[1]);
		return -1;
	}

	if(!readBootSector(disk)){
		fprintf(stderr,"Error reading Boot Sector!\n");
		return -2;
	};

	if(!readFat(disk)){
		fprintf(stderr,"Error reading FAT!\n");
		free(Fat);
		return -3;
	}
	if(!readRootDirectory(disk)){
		fprintf(stderr,"Error reading FAT!\n");
		free(Fat);
		free(RootDirectory);
		return -4;
	}

	DirectoryEntry* fileEntry = findFile(argv[2]);
	if(!fileEntry){
		fprintf(stderr,"Could not find file %s!\n",argv[2]);
		free(Fat);
		free(RootDirectory);
		return -5;
	}

	uint8_t* buffer = (uint8_t*)malloc(fileEntry->size+BootSector.BytesPerSector);
	if(!readFile(fileEntry,disk,buffer)){
		fprintf(stderr,"Error reading from file %s!\n",argv[2]);
		free(Fat);
		free(RootDirectory);
		free(buffer);
		return -6;
	}

	for(size_t i = 0;i<fileEntry->size;i++){
		if(isprint(buffer[i])) fputc(buffer[i],stdout);
		else printf("<%02x>",buffer[i]);
	}
	printf("\n");

	free(buffer);
	free(Fat);
	free(RootDirectory);
	return 0;
}
