unit progmanager;

interface

uses
    tracer, console,
    //progs
    base64_prog, md5sum, shell, terminal, 
    edit, netlog, themer,
    memview, udpcat, dhclient, vbeinfo;

procedure init();

implementation

procedure init();
begin
    tracer.push_trace('progmanager.shell.init');
    shell.init();
    tracer.push_trace('progmanager.memview.init');
    memview.init();
    tracer.push_trace('progmanager.themer.init');
    themer.init();
    tracer.push_trace('progmanager.netlog.init');
    netlog.init();
    tracer.push_trace('progmanager.edit.init');
    edit.init();
    tracer.push_trace('progmanager.udpcat.init');
    udpcat.init();
    tracer.push_trace('progmanager.md5sum.init');
    md5sum.init();
    tracer.push_trace('progmanager.base64_prog.init');
    base64_prog.init();
    tracer.push_trace('progmanager.dhclient.init');
    dhclient.init();
    vbeinfo.init();

    tracer.push_trace('progmanager.terminal.init');
    terminal.run();   
end;

end.