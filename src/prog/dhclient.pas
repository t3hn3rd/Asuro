{ 
	Prog->DHClient - DHCP Configuration Management.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit dhclient;

interface

uses
    console, terminal, keyboard, util, strings, tracer, dhcp;

procedure init();

implementation

procedure run(Params : PParamList);
begin
    tracer.push_trace('dhclient.run');
    DHCPDiscover();
end;

procedure init();
begin
    tracer.push_trace('dhclient.init');
    terminal.registerCommand('DHClient', @Run, 'Run the DHCP configuration utility.');
end;

end.