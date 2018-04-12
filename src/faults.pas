unit faults;

interface

uses
    ACE, BPE, BTSSE, CFE, CSOE, DBGE, DBZ, DFE, GPF, IDOE, IOPE, MCE,
    NCE, NMIE, OOBE, PF, SFE, SNPE, UIE;

procedure init;

implementation

procedure init;
begin
    ACE.register();
    BPE.register();
    BTSSE.register();
    CFE.register();
    CSOE.register();
    DBGE.register();
    DBZ.register();
    DFE.register();
    GPF.register();
    IDOE.register();
    IOPE.register();
    MCE.register();
    NCE.register();
    NMIE.register();
    OOBE.register();
    PF.register();
    SFE.register();
    SNPE.register();
    UIE.register();
end;

end.