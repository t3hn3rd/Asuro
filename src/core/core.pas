unit core;

interface

uses
    boot.mgr,
    core.rand,
    driver.timer.rtc;

implementation

procedure init();
begin
    core.rand.srand((getDateTime.Seconds SHL 24) OR (getDateTime.Minutes SHL 16) OR (getDateTime.Hours SHL 8) OR (getDateTime.Day));
end;

initialization
    boot.mgr.registerBoot('core', @init, 'Core Initialization', BOOT_MGR_BARRIER_LATE);

end.