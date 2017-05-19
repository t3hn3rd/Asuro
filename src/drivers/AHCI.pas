{ ************************************************
  * Asuro
  * Unit: Drivers/AHCI
  * Description: AHCI SATA Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

  unit AHCI

  interface

  uses 
    system,
    util,
    isr46;

    type

        TFIS_Type = (
            REG_H2D, REG_D2H,
            DMA_ACT, DMA_SETUP,
            DATA, BIST,
            PIO_SETUP, DEV_BITS
        );

        TFIS_REG_H2D bitpacked record
            fis_type     : uint8;
            port_mult    : UBit4;
            rsv0         : UBit3;
            coc          : boolean;
            command      : uint8;
            feature_low  : uint8;
            lba0         : uint8;
            lba1         : uint8;
            lba2         : uint8;
            device       : uint8;
            lba3         : uint8;
            lba4         : uint8;
            lba5         : uint8;
            feature_high : uint8;
            count_low    : uint8;
            count_high   : uint8;
            icc          : uint8;
            control      : uint8;
            rsvl         : uint32;
        end; 

    var

    implementation 

    end.