{ ************************************************
  * Asuro
  * Unit: Drivers/IDE
  * Description: IDE Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit IDE;

{$MACRO ON} 
{$define ATA_SR_BSY               :=  0x80 } 
{$define ATA_SR_DRDY              :=  0x40 }
{$define ATA_SR_DF                :=  0x20 }
{$define ATA_SR_DSC               :=  0x10 }
{$define ATA_SR_DRQ               :=  0x08 }
{$define ATA_SR_CORR              :=  0x04 }
{$define ATA_SR_IDX               :=  0x02 }
{$define ATA_SR_ERR               :=  0x01 }

{$define ATA_CMD_READ_PIO         :=   0x20 }
{$define ATA_CMD_READ_PIO_EXT     :=   0x24 }
{$define ATA_CMD_READ_DMA         :=   0xC8 }
{$define ATA_CMD_READ_DMA_EXT     :=   0x25 }
{$define ATA_CMD_WRITE_PIO        :=   0x30 }
{$define ATA_CMD_WRITE_PIO_EXT    :=   0x34 }
{$define ATA_CMD_WRITE_DMA        :=   0xCA }
{$define ATA_CMD_WRITE_DMA_EXT    :=   0x35 }
{$define ATA_CMD_CACHE_FLUSH      :=   0xE7 }
{$define ATA_CMD_CACHE_FLUSH_EXT  :=   0xEA }
{$define ATA_CMD_PACKET           :=   0xA0 }
{$define ATA_CMD_IDENTIFY_PACKET  :=   0xA1 }
{$define ATA_CMD_IDENTIFY         :=   0xEC }

{$define      ATAPI_CMD_READ      :=   0xA8 }
{$define      ATAPI_CMD_EJECT     :=   0x1B }

{$define ATA_IDENT_DEVICETYPE     :=   0    }
{$define ATA_IDENT_CYLINDERS      :=   2    }
{$define ATA_IDENT_HEADS          :=   6    }
{$define ATA_IDENT_SECTORS        :=   12   }
{$define ATA_IDENT_SERIAL         :=   20   }
{$define ATA_IDENT_MODEL          :=   54   }
{$define ATA_IDENT_CAPABILITIES   :=   98   }
{$define ATA_IDENT_FIELDVALID     :=   106  }
{$define ATA_IDENT_MAX_LBA        :=   120  }
{$define ATA_IDENT_COMMANDSETS    :=   164  }
{$define ATA_IDENT_MAX_LBA_EXT    :=   200  }

{$define IDE_ATA                  :=   0x00 }
{$define IDE_ATAPI                :=   0x01 }

{$define ATA_MASTER               :=   0x00 }
{$define ATA_SLAVE                :=   0x01 }

{$define ATA_REG_DATA             :=  0x00  }
{$define ATA_REG_ERROR            :=  0x01  }
{$define ATA_REG_FEATURES         :=  0x01  }
{$define ATA_REG_SECCOUNT0        :=  0x02  }
{$define ATA_REG_LBA0             :=  0x03  }
{$define ATA_REG_LBA1             :=  0x04  }
{$define ATA_REG_LBA2             :=  0x05  }
{$define ATA_REG_HDDEVSEL         :=  0x06  }
{$define ATA_REG_COMMAND          :=  0x07  }
{$define ATA_REG_STATUS           :=  0x07  }
{$define ATA_REG_SECCOUNT1        :=  0x08  }
{$define ATA_REG_LBA3             :=  0x09  }
{$define ATA_REG_LBA4             :=  0x0A  }
{$define ATA_REG_LBA5             :=  0x0B  }
{$define ATA_REG_CONTROL          :=  0x0C  }
{$define ATA_REG_ALTSTATUS        :=  0x0C  }
{$define ATA_REG_DEVADDRESS       :=  0x0D  }

interface

uses
    util,
    PCI,
    console;

type 

    IDE_Channel_Registers = record
        base  : uint16;
        ctrl  : uint16;
        bmide : uint16;
        nIEN  : char;
    end;

    IDE_Device = record
        Reserved     : uint8;
        Channel      : uint8;
        Drive        : uint8;
        dType        : uint16;
        Signature    : uint16;
        Capabilities : uint16;
        CommandSets  : uint32;
        Size         : uint32;
        Model        : array[0..41] of char;
    end;

var 
    SATA1 = uint32;
    SATA2 = uint32;
    SATA3 = uint32;
    SATA4 = uint32;
    BUS_MASTER = uint32;

    channels : array[0..1] of IDE_Channel_Registers;
    devices  : array[0..3] of IDE_Device;

    ide_buff : array[0..2048] of char = (0);
    ide_irq_invoked : char = 0;
    atapi_packet : array[0..12] of char = (0xAB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    

procedure init(TPCI_Device : device);

begin
    
end;

implementation

function ide_read(channel : uint8; reg : uint8) : uint8;
begin
    if reg > $07 and reg < $80 then ide_write(channel, ATA_REG_CONTROL, $80 | channels[channel].nIEN);
    if reg < $08 then ide_read := inb(channels[channel].base + reg - $00);
    else if reg < $0C then ide_read := inb(channels[channel].base  + reg - $06);
    else if reg < $0E then ide_read := inb(channels[channel].ctrl + reg - $0A);
    else if reg < $16 then ide_read := inb(channels[channel].bmide + reg - $0E);
    if reg > $07 and reg < $0C then ide_write(channel, ATA_REG_CONTROL, channels[channel].nIEN);
end;

procedure ide_write(channel : uint8; reg : uint8; data : uint8) 
begin
    if reg > $07 and reg < $80 then ide_write(channel, ATA_REG_CONTROL, $80 | channels[channel].nIEN);
    if reg < $08 then outb(channels[channel].base + reg - $00, data);
    else if reg < $0C then outb(channels[channel].base  + reg - $06, data);
    else if reg < $0E then outb(channels[channel].ctrl + reg - $0A, data);
    else if reg < $16 then outb(channels[channel].bmide + reg - $0E, data);
    if reg > $07 and reg < $0C then ide_write(channel, ATA_REG_CONTROL, channels[channel].nIEN);
end;

procedure init(TPCI_Device : device) begin
    SATA1 = device.address0;
    SATA2 = device.address1;
    SATA3 = device.address2;
    SATA4 = device.address3;
    BUS_MASTER = device.address4;
end;

end.