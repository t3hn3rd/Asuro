//  Copyright 2021 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
	ISR->ISRManager - Interrupt Service Routine Registration, Dispatch & Management.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit isrmanager;

interface

uses
    isr, idt, isr_types, util;

type
    TISRHook = procedure();
    TISRNHookArray = Array[0..MAX_HOOKS] of TISRHook;
    TISRHookArray = Array[0..255] of TISRNHookArray;

procedure init;
procedure registerISR(INT_N : uint8; callback : TISRHook);
procedure dispatchHooks(INT_N : uint8);

implementation
uses 
syslog, ioapic;

var
    Hooks : TISRHookArray;

procedure registerISR(INT_N : uint8; callback : TISRHook);
var
    i : uint8;

begin
    i:=0;
    while (Hooks[INT_N][i] <> nil) AND (i < MAX_HOOKS) do begin
        i:= i + 1;
    end;
    if i <= MAX_HOOKS then begin
        Hooks[INT_N][i]:= callback;
    end;
end;

procedure dispatchHooks(INT_N : uint8);
var
    i : uint8;
begin
    for i:=0 to MAX_HOOKS do begin
        if Hooks[INT_N][i] <> nil then Hooks[INT_N][i]();
    end;
end;

procedure ISR_N(INT_N : uint8);
var
    i : uint8;

begin

	// if int_n <> $20 then begin
	// 	console.writestring('ISR: ');
	// 	console.writehexpair(Int_N);
	// 	console.writestringln(' called');
	// end;

    for i:=0 to MAX_HOOKS do begin
        if Hooks[INT_N][i] <> nil then Hooks[INT_N][i]();
    end;
    { Send EOI to Local APIC (needed for IOAPIC-delivered interrupts).
      Safe no-op when IOAPIC is not present. }
    ioapic.lapic_eoi();
    { Send EOI to 8259 PIC (slave then master) }
    if (INT_N >= 40) then outb($A0, $20);
    outb($20, $20);
end;

procedure ISR_0; interrupt;
begin   
	asm
		MOV IntReg, EBP
	end;
	ISR_N(0);
end;
 
procedure ISR_1; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(1);
end;
 
procedure ISR_2; interrupt;
begin
    asm
		MOV IntReg, EBP	
    end;
	ISR_N(2);
end;
 
procedure ISR_3; interrupt;
begin
    asm
		MOV IntReg, EBP	
    end;
	ISR_N(3);
end;
 
procedure ISR_4; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(4);
end;
 
procedure ISR_5; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(5);
end;
 
procedure ISR_6; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(6);
end;
 
procedure ISR_7; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(7);
end;
 
procedure ISR_8; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(8);
end;
 
procedure ISR_9; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(9);
end;
 
procedure ISR_10; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(10);
end;
 
procedure ISR_11; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(11);
end;
 
procedure ISR_12; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(12);
end;
 
procedure ISR_13; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(13);
end;
 
procedure ISR_14; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(14);
end;
 
procedure ISR_15; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(15);
end;
 
procedure ISR_16; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(16);
end;
 
procedure ISR_17; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(17);
end;
 
procedure ISR_18; interrupt;
begin
    asm
		MOV IntReg, EBP	
	end;
	ISR_N(18);
end;
 
procedure ISR_19; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(19);
end;
 
procedure ISR_20; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(20);
end;
 
procedure ISR_21; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(21);
end;
 
procedure ISR_22; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(22);
end;
 
procedure ISR_23; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(23);
end;
 
procedure ISR_24; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(24);
end;
 
procedure ISR_25; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(25);
end;
 
procedure ISR_26; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(26);
end;
 
procedure ISR_27; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(27);
end;
 
procedure ISR_28; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(28);
end;
 
procedure ISR_29; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(29);
end;
 
procedure ISR_30; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(30);
end;
 
procedure ISR_31; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(31);
end;
 
procedure ISR_32; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(32);
end;
 
procedure ISR_33; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(33);
end;
 
procedure ISR_34; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(34);
end;
 
procedure ISR_35; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(35);
end;
 
procedure ISR_36; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(36);
end;
 
procedure ISR_37; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(37);
end;
 
procedure ISR_38; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(38);
end;
 
procedure ISR_39; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(39);
end;
 
procedure ISR_40; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(40);
end;
 
procedure ISR_41; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(41);
end;
 
procedure ISR_42; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(42);
end;
 
procedure ISR_43; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(43);
end;
 
procedure ISR_44; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(44);
end;
 
procedure ISR_45; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(45);
end;
 
procedure ISR_46; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(46);
end;
 
procedure ISR_47; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(47);
end;
 
procedure ISR_48; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(48);
end;
 
procedure ISR_49; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(49);
end;
 
procedure ISR_50; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(50);
end;
 
procedure ISR_51; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(51);
end;
 
procedure ISR_52; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(52);
end;
 
procedure ISR_53; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(53);
end;
 
procedure ISR_54; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(54);
end;
 
procedure ISR_55; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(55);
end;
 
procedure ISR_56; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(56);
end;
 
procedure ISR_57; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(57);
end;
 
procedure ISR_58; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(58);
end;
 
procedure ISR_59; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(59);
end;
 
procedure ISR_60; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(60);
end;
 
procedure ISR_61; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(61);
end;
 
procedure ISR_62; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(62);
end;
 
procedure ISR_63; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(63);
end;
 
procedure ISR_64; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(64);
end;
 
procedure ISR_65; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(65);
end;
 
procedure ISR_66; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(66);
end;
 
procedure ISR_67; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(67);
end;
 
procedure ISR_68; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(68);
end;
 
procedure ISR_69; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(69);
end;
 
procedure ISR_70; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(70);
end;
 
procedure ISR_71; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(71);
end;
 
procedure ISR_72; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(72);
end;
 
procedure ISR_73; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(73);
end;
 
procedure ISR_74; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(74);
end;
 
procedure ISR_75; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(75);
end;
 
procedure ISR_76; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(76);
end;
 
procedure ISR_77; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(77);
end;
 
procedure ISR_78; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(78);
end;
 
procedure ISR_79; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(79);
end;
 
procedure ISR_80; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(80);
end;
 
procedure ISR_81; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(81);
end;
 
procedure ISR_82; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(82);
end;
 
procedure ISR_83; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(83);
end;
 
procedure ISR_84; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(84);
end;
 
procedure ISR_85; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(85);
end;
 
procedure ISR_86; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(86);
end;
 
procedure ISR_87; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(87);
end;
 
procedure ISR_88; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(88);
end;
 
procedure ISR_89; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(89);
end;
 
procedure ISR_90; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(90);
end;
 
procedure ISR_91; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(91);
end;
 
procedure ISR_92; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(92);
end;
 
procedure ISR_93; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(93);
end;
 
procedure ISR_94; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(94);
end;
 
procedure ISR_95; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(95);
end;
 
procedure ISR_96; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(96);
end;
 
procedure ISR_97; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(97);
end;
 
procedure ISR_98; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(98);
end;
 
procedure ISR_99; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(99);
end;
 
procedure ISR_100; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(100);
end;
 
procedure ISR_101; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(101);
end;
 
procedure ISR_102; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(102);
end;
 
procedure ISR_103; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(103);
end;
 
procedure ISR_104; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(104);
end;
 
procedure ISR_105; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(105);
end;
 
procedure ISR_106; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(106);
end;
 
procedure ISR_107; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(107);
end;
 
procedure ISR_108; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(108);
end;
 
procedure ISR_109; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(109);
end;
 
procedure ISR_110; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(110);
end;
 
procedure ISR_111; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(111);
end;
 
procedure ISR_112; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(112);
end;
 
procedure ISR_113; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(113);
end;
 
procedure ISR_114; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(114);
end;
 
procedure ISR_115; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(115);
end;
 
procedure ISR_116; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(116);
end;
 
procedure ISR_117; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(117);
end;
 
procedure ISR_118; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(118);
end;
 
procedure ISR_119; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(119);
end;
 
procedure ISR_120; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(120);
end;
 
procedure ISR_121; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(121);
end;
 
procedure ISR_122; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(122);
end;
 
procedure ISR_123; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(123);
end;
 
procedure ISR_124; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(124);
end;
 
procedure ISR_125; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(125);
end;
 
procedure ISR_126; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(126);
end;
 
procedure ISR_127; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(127);
end;
 
procedure ISR_128; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(128);
end;
 
procedure ISR_129; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(129);
end;
 
procedure ISR_130; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(130);
end;
 
procedure ISR_131; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(131);
end;
 
procedure ISR_132; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(132);
end;
 
procedure ISR_133; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(133);
end;
 
procedure ISR_134; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(134);
end;
 
procedure ISR_135; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(135);
end;
 
procedure ISR_136; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(136);
end;
 
procedure ISR_137; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(137);
end;
 
procedure ISR_138; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(138);
end;
 
procedure ISR_139; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(139);
end;
 
procedure ISR_140; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(140);
end;
 
procedure ISR_141; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(141);
end;
 
procedure ISR_142; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(142);
end;
 
procedure ISR_143; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(143);
end;
 
procedure ISR_144; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(144);
end;
 
procedure ISR_145; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(145);
end;
 
procedure ISR_146; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(146);
end;
 
procedure ISR_147; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(147);
end;
 
procedure ISR_148; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(148);
end;
 
procedure ISR_149; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(149);
end;
 
procedure ISR_150; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(150);
end;
 
procedure ISR_151; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(151);
end;
 
procedure ISR_152; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(152);
end;
 
procedure ISR_153; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(153);
end;
 
procedure ISR_154; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(154);
end;
 
procedure ISR_155; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(155);
end;
 
procedure ISR_156; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(156);
end;
 
procedure ISR_157; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(157);
end;
 
procedure ISR_158; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(158);
end;
 
procedure ISR_159; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(159);
end;
 
procedure ISR_160; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(160);
end;
 
procedure ISR_161; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(161);
end;
 
procedure ISR_162; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(162);
end;
 
procedure ISR_163; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(163);
end;
 
procedure ISR_164; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(164);
end;
 
procedure ISR_165; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(165);
end;
 
procedure ISR_166; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(166);
end;
 
procedure ISR_167; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(167);
end;
 
procedure ISR_168; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(168);
end;
 
procedure ISR_169; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(169);
end;
 
procedure ISR_170; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(170);
end;
 
procedure ISR_171; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(171);
end;
 
procedure ISR_172; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(172);
end;
 
procedure ISR_173; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(173);
end;
 
procedure ISR_174; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(174);
end;
 
procedure ISR_175; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(175);
end;
 
procedure ISR_176; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(176);
end;
 
procedure ISR_177; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(177);
end;
 
procedure ISR_178; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(178);
end;
 
procedure ISR_179; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(179);
end;
 
procedure ISR_180; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(180);
end;
 
procedure ISR_181; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(181);
end;
 
procedure ISR_182; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(182);
end;
 
procedure ISR_183; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(183);
end;
 
procedure ISR_184; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(184);
end;
 
procedure ISR_185; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(185);
end;
 
procedure ISR_186; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(186);
end;
 
procedure ISR_187; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(187);
end;
 
procedure ISR_188; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(188);
end;
 
procedure ISR_189; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(189);
end;
 
procedure ISR_190; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(190);
end;
 
procedure ISR_191; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(191);
end;
 
procedure ISR_192; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(192);
end;
 
procedure ISR_193; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(193);
end;
 
procedure ISR_194; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(194);
end;
 
procedure ISR_195; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(195);
end;
 
procedure ISR_196; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(196);
end;
 
procedure ISR_197; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(197);
end;
 
procedure ISR_198; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(198);
end;
 
procedure ISR_199; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(199);
end;
 
procedure ISR_200; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(200);
end;
 
procedure ISR_201; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(201);
end;
 
procedure ISR_202; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(202);
end;
 
procedure ISR_203; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(203);
end;
 
procedure ISR_204; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(204);
end;
 
procedure ISR_205; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(205);
end;
 
procedure ISR_206; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(206);
end;
 
procedure ISR_207; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(207);
end;
 
procedure ISR_208; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(208);
end;
 
procedure ISR_209; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(209);
end;
 
procedure ISR_210; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(210);
end;
 
procedure ISR_211; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(211);
end;
 
procedure ISR_212; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(212);
end;
 
procedure ISR_213; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(213);
end;
 
procedure ISR_214; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(214);
end;
 
procedure ISR_215; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(215);
end;
 
procedure ISR_216; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(216);
end;
 
procedure ISR_217; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(217);
end;
 
procedure ISR_218; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(218);
end;
 
procedure ISR_219; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(219);
end;
 
procedure ISR_220; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(220);
end;
 
procedure ISR_221; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(221);
end;
 
procedure ISR_222; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(222);
end;
 
procedure ISR_223; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(223);
end;
 
procedure ISR_224; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(224);
end;
 
procedure ISR_225; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(225);
end;
 
procedure ISR_226; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(226);
end;
 
procedure ISR_227; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(227);
end;
 
procedure ISR_228; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(228);
end;
 
procedure ISR_229; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(229);
end;
 
procedure ISR_230; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(230);
end;
 
procedure ISR_231; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(231);
end;
 
procedure ISR_232; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(232);
end;
 
procedure ISR_233; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(233);
end;
 
procedure ISR_234; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(234);
end;
 
procedure ISR_235; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(235);
end;
 
procedure ISR_236; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(236);
end;
 
procedure ISR_237; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(237);
end;
 
procedure ISR_238; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(238);
end;
 
procedure ISR_239; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(239);
end;
 
procedure ISR_240; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(240);
end;
 
procedure ISR_241; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(241);
end;
 
procedure ISR_242; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(242);
end;
 
procedure ISR_243; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(243);
end;
 
procedure ISR_244; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(244);
end;
 
procedure ISR_245; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(245);
end;
 
procedure ISR_246; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(246);
end;
 
procedure ISR_247; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(247);
end;
 
procedure ISR_248; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(248);
end;
 
procedure ISR_249; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(249);
end;
 
procedure ISR_250; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(250);
end;
 
procedure ISR_251; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(251);
end;
 
procedure ISR_252; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(252);
end;
 
procedure ISR_253; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(253);
end;
 
procedure ISR_254; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(254);
end;
 
procedure ISR_255; interrupt;
begin
    asm
		MOV IntReg, EBP
	end;
	ISR_N(255);
end;

procedure init;
var
    i, j : uint8;

begin
    for i:=0 to 255 do begin
        for j:=0 to MAX_HOOKS do begin
            Hooks[i][j]:= nil;
        end;
    end;
    IDT.set_gate(0, uint32(@ISR_0), $08, ISR_RING_0);
    IDT.set_gate(1, uint32(@ISR_1), $08, ISR_RING_0);
    IDT.set_gate(2, uint32(@ISR_2), $08, ISR_RING_0);
    IDT.set_gate(3, uint32(@ISR_3), $08, ISR_RING_0);
    IDT.set_gate(4, uint32(@ISR_4), $08, ISR_RING_0);
    IDT.set_gate(5, uint32(@ISR_5), $08, ISR_RING_0);
    IDT.set_gate(6, uint32(@ISR_6), $08, ISR_RING_0);
    IDT.set_gate(7, uint32(@ISR_7), $08, ISR_RING_0);
    IDT.set_gate(8, uint32(@ISR_8), $08, ISR_RING_0);
    IDT.set_gate(9, uint32(@ISR_9), $08, ISR_RING_0);
    IDT.set_gate(10, uint32(@ISR_10), $08, ISR_RING_0);
    IDT.set_gate(11, uint32(@ISR_11), $08, ISR_RING_0);
    IDT.set_gate(12, uint32(@ISR_12), $08, ISR_RING_0);
    IDT.set_gate(13, uint32(@ISR_13), $08, ISR_RING_0);
    IDT.set_gate(14, uint32(@ISR_14), $08, ISR_RING_0);
    IDT.set_gate(15, uint32(@ISR_15), $08, ISR_RING_0);
    IDT.set_gate(16, uint32(@ISR_16), $08, ISR_RING_0);
    IDT.set_gate(17, uint32(@ISR_17), $08, ISR_RING_0);
    IDT.set_gate(18, uint32(@ISR_18), $08, ISR_RING_0);
    IDT.set_gate(19, uint32(@ISR_19), $08, ISR_RING_0);
    IDT.set_gate(20, uint32(@ISR_20), $08, ISR_RING_0);
    IDT.set_gate(21, uint32(@ISR_21), $08, ISR_RING_0);
    IDT.set_gate(22, uint32(@ISR_22), $08, ISR_RING_0);
    IDT.set_gate(23, uint32(@ISR_23), $08, ISR_RING_0);
    IDT.set_gate(24, uint32(@ISR_24), $08, ISR_RING_0);
    IDT.set_gate(25, uint32(@ISR_25), $08, ISR_RING_0);
    IDT.set_gate(26, uint32(@ISR_26), $08, ISR_RING_0);
    IDT.set_gate(27, uint32(@ISR_27), $08, ISR_RING_0);
    IDT.set_gate(28, uint32(@ISR_28), $08, ISR_RING_0);
    IDT.set_gate(29, uint32(@ISR_29), $08, ISR_RING_0);
    IDT.set_gate(30, uint32(@ISR_30), $08, ISR_RING_0);
    IDT.set_gate(31, uint32(@ISR_31), $08, ISR_RING_0);
    IDT.set_gate(32, uint32(@ISR_32), $08, ISR_RING_0);
    IDT.set_gate(33, uint32(@ISR_33), $08, ISR_RING_0);
    IDT.set_gate(34, uint32(@ISR_34), $08, ISR_RING_0);
    IDT.set_gate(35, uint32(@ISR_35), $08, ISR_RING_0);
    IDT.set_gate(36, uint32(@ISR_36), $08, ISR_RING_0);
    IDT.set_gate(37, uint32(@ISR_37), $08, ISR_RING_0);
    IDT.set_gate(38, uint32(@ISR_38), $08, ISR_RING_0);
    IDT.set_gate(39, uint32(@ISR_39), $08, ISR_RING_0);
    IDT.set_gate(40, uint32(@ISR_40), $08, ISR_RING_0);
    IDT.set_gate(41, uint32(@ISR_41), $08, ISR_RING_0);
    IDT.set_gate(42, uint32(@ISR_42), $08, ISR_RING_0);
    IDT.set_gate(43, uint32(@ISR_43), $08, ISR_RING_0);
    IDT.set_gate(44, uint32(@ISR_44), $08, ISR_RING_0);
    IDT.set_gate(45, uint32(@ISR_45), $08, ISR_RING_0);
    IDT.set_gate(46, uint32(@ISR_46), $08, ISR_RING_0);
    IDT.set_gate(47, uint32(@ISR_47), $08, ISR_RING_0);
    IDT.set_gate(48, uint32(@ISR_48), $08, ISR_RING_0);
    IDT.set_gate(49, uint32(@ISR_49), $08, ISR_RING_0);
    IDT.set_gate(50, uint32(@ISR_50), $08, ISR_RING_0);
    IDT.set_gate(51, uint32(@ISR_51), $08, ISR_RING_0);
    IDT.set_gate(52, uint32(@ISR_52), $08, ISR_RING_0);
    IDT.set_gate(53, uint32(@ISR_53), $08, ISR_RING_0);
    IDT.set_gate(54, uint32(@ISR_54), $08, ISR_RING_0);
    IDT.set_gate(55, uint32(@ISR_55), $08, ISR_RING_0);
    IDT.set_gate(56, uint32(@ISR_56), $08, ISR_RING_0);
    IDT.set_gate(57, uint32(@ISR_57), $08, ISR_RING_0);
    IDT.set_gate(58, uint32(@ISR_58), $08, ISR_RING_0);
    IDT.set_gate(59, uint32(@ISR_59), $08, ISR_RING_0);
    IDT.set_gate(60, uint32(@ISR_60), $08, ISR_RING_0);
    IDT.set_gate(61, uint32(@ISR_61), $08, ISR_RING_0);
    IDT.set_gate(62, uint32(@ISR_62), $08, ISR_RING_0);
    IDT.set_gate(63, uint32(@ISR_63), $08, ISR_RING_0);
    IDT.set_gate(64, uint32(@ISR_64), $08, ISR_RING_0);
    IDT.set_gate(65, uint32(@ISR_65), $08, ISR_RING_0);
    IDT.set_gate(66, uint32(@ISR_66), $08, ISR_RING_0);
    IDT.set_gate(67, uint32(@ISR_67), $08, ISR_RING_0);
    IDT.set_gate(68, uint32(@ISR_68), $08, ISR_RING_0);
    IDT.set_gate(69, uint32(@ISR_69), $08, ISR_RING_0);
    IDT.set_gate(70, uint32(@ISR_70), $08, ISR_RING_0);
    IDT.set_gate(71, uint32(@ISR_71), $08, ISR_RING_0);
    IDT.set_gate(72, uint32(@ISR_72), $08, ISR_RING_0);
    IDT.set_gate(73, uint32(@ISR_73), $08, ISR_RING_0);
    IDT.set_gate(74, uint32(@ISR_74), $08, ISR_RING_0);
    IDT.set_gate(75, uint32(@ISR_75), $08, ISR_RING_0);
    IDT.set_gate(76, uint32(@ISR_76), $08, ISR_RING_0);
    IDT.set_gate(77, uint32(@ISR_77), $08, ISR_RING_0);
    IDT.set_gate(78, uint32(@ISR_78), $08, ISR_RING_0);
    IDT.set_gate(79, uint32(@ISR_79), $08, ISR_RING_0);
    IDT.set_gate(80, uint32(@ISR_80), $08, ISR_RING_0);
    IDT.set_gate(81, uint32(@ISR_81), $08, ISR_RING_0);
    IDT.set_gate(82, uint32(@ISR_82), $08, ISR_RING_0);
    IDT.set_gate(83, uint32(@ISR_83), $08, ISR_RING_0);
    IDT.set_gate(84, uint32(@ISR_84), $08, ISR_RING_0);
    IDT.set_gate(85, uint32(@ISR_85), $08, ISR_RING_0);
    IDT.set_gate(86, uint32(@ISR_86), $08, ISR_RING_0);
    IDT.set_gate(87, uint32(@ISR_87), $08, ISR_RING_0);
    IDT.set_gate(88, uint32(@ISR_88), $08, ISR_RING_0);
    IDT.set_gate(89, uint32(@ISR_89), $08, ISR_RING_0);
    IDT.set_gate(90, uint32(@ISR_90), $08, ISR_RING_0);
    IDT.set_gate(91, uint32(@ISR_91), $08, ISR_RING_0);
    IDT.set_gate(92, uint32(@ISR_92), $08, ISR_RING_0);
    IDT.set_gate(93, uint32(@ISR_93), $08, ISR_RING_0);
    IDT.set_gate(94, uint32(@ISR_94), $08, ISR_RING_0);
    IDT.set_gate(95, uint32(@ISR_95), $08, ISR_RING_0);
    IDT.set_gate(96, uint32(@ISR_96), $08, ISR_RING_0);
    IDT.set_gate(97, uint32(@ISR_97), $08, ISR_RING_0);
    IDT.set_gate(98, uint32(@ISR_98), $08, ISR_RING_0);
    IDT.set_gate(99, uint32(@ISR_99), $08, ISR_RING_0);
    IDT.set_gate(100, uint32(@ISR_100), $08, ISR_RING_0);
    IDT.set_gate(101, uint32(@ISR_101), $08, ISR_RING_0);
    IDT.set_gate(102, uint32(@ISR_102), $08, ISR_RING_0);
    IDT.set_gate(103, uint32(@ISR_103), $08, ISR_RING_0);
    IDT.set_gate(104, uint32(@ISR_104), $08, ISR_RING_0);
    IDT.set_gate(105, uint32(@ISR_105), $08, ISR_RING_0);
    IDT.set_gate(106, uint32(@ISR_106), $08, ISR_RING_0);
    IDT.set_gate(107, uint32(@ISR_107), $08, ISR_RING_0);
    IDT.set_gate(108, uint32(@ISR_108), $08, ISR_RING_0);
    IDT.set_gate(109, uint32(@ISR_109), $08, ISR_RING_0);
    IDT.set_gate(110, uint32(@ISR_110), $08, ISR_RING_0);
    IDT.set_gate(111, uint32(@ISR_111), $08, ISR_RING_0);
    IDT.set_gate(112, uint32(@ISR_112), $08, ISR_RING_0);
    IDT.set_gate(113, uint32(@ISR_113), $08, ISR_RING_0);
    IDT.set_gate(114, uint32(@ISR_114), $08, ISR_RING_0);
    IDT.set_gate(115, uint32(@ISR_115), $08, ISR_RING_0);
    IDT.set_gate(116, uint32(@ISR_116), $08, ISR_RING_0);
    IDT.set_gate(117, uint32(@ISR_117), $08, ISR_RING_0);
    IDT.set_gate(118, uint32(@ISR_118), $08, ISR_RING_0);
    IDT.set_gate(119, uint32(@ISR_119), $08, ISR_RING_0);
    IDT.set_gate(120, uint32(@ISR_120), $08, ISR_RING_0);
    IDT.set_gate(121, uint32(@ISR_121), $08, ISR_RING_0);
    IDT.set_gate(122, uint32(@ISR_122), $08, ISR_RING_0);
    IDT.set_gate(123, uint32(@ISR_123), $08, ISR_RING_0);
    IDT.set_gate(124, uint32(@ISR_124), $08, ISR_RING_0);
    IDT.set_gate(125, uint32(@ISR_125), $08, ISR_RING_0);
    IDT.set_gate(126, uint32(@ISR_126), $08, ISR_RING_0);
    IDT.set_gate(127, uint32(@ISR_127), $08, ISR_RING_0);
    IDT.set_gate(128, uint32(@ISR_128), $08, ISR_RING_0);
    IDT.set_gate(129, uint32(@ISR_129), $08, ISR_RING_0);
    IDT.set_gate(130, uint32(@ISR_130), $08, ISR_RING_0);
    IDT.set_gate(131, uint32(@ISR_131), $08, ISR_RING_0);
    IDT.set_gate(132, uint32(@ISR_132), $08, ISR_RING_0);
    IDT.set_gate(133, uint32(@ISR_133), $08, ISR_RING_0);
    IDT.set_gate(134, uint32(@ISR_134), $08, ISR_RING_0);
    IDT.set_gate(135, uint32(@ISR_135), $08, ISR_RING_0);
    IDT.set_gate(136, uint32(@ISR_136), $08, ISR_RING_0);
    IDT.set_gate(137, uint32(@ISR_137), $08, ISR_RING_0);
    IDT.set_gate(138, uint32(@ISR_138), $08, ISR_RING_0);
    IDT.set_gate(139, uint32(@ISR_139), $08, ISR_RING_0);
    IDT.set_gate(140, uint32(@ISR_140), $08, ISR_RING_0);
    IDT.set_gate(141, uint32(@ISR_141), $08, ISR_RING_0);
    IDT.set_gate(142, uint32(@ISR_142), $08, ISR_RING_0);
    IDT.set_gate(143, uint32(@ISR_143), $08, ISR_RING_0);
    IDT.set_gate(144, uint32(@ISR_144), $08, ISR_RING_0);
    IDT.set_gate(145, uint32(@ISR_145), $08, ISR_RING_0);
    IDT.set_gate(146, uint32(@ISR_146), $08, ISR_RING_0);
    IDT.set_gate(147, uint32(@ISR_147), $08, ISR_RING_0);
    IDT.set_gate(148, uint32(@ISR_148), $08, ISR_RING_0);
    IDT.set_gate(149, uint32(@ISR_149), $08, ISR_RING_0);
    IDT.set_gate(150, uint32(@ISR_150), $08, ISR_RING_0);
    IDT.set_gate(151, uint32(@ISR_151), $08, ISR_RING_0);
    IDT.set_gate(152, uint32(@ISR_152), $08, ISR_RING_0);
    IDT.set_gate(153, uint32(@ISR_153), $08, ISR_RING_0);
    IDT.set_gate(154, uint32(@ISR_154), $08, ISR_RING_0);
    IDT.set_gate(155, uint32(@ISR_155), $08, ISR_RING_0);
    IDT.set_gate(156, uint32(@ISR_156), $08, ISR_RING_0);
    IDT.set_gate(157, uint32(@ISR_157), $08, ISR_RING_0);
    IDT.set_gate(158, uint32(@ISR_158), $08, ISR_RING_0);
    IDT.set_gate(159, uint32(@ISR_159), $08, ISR_RING_0);
    IDT.set_gate(160, uint32(@ISR_160), $08, ISR_RING_0);
    IDT.set_gate(161, uint32(@ISR_161), $08, ISR_RING_0);
    IDT.set_gate(162, uint32(@ISR_162), $08, ISR_RING_0);
    IDT.set_gate(163, uint32(@ISR_163), $08, ISR_RING_0);
    IDT.set_gate(164, uint32(@ISR_164), $08, ISR_RING_0);
    IDT.set_gate(165, uint32(@ISR_165), $08, ISR_RING_0);
    IDT.set_gate(166, uint32(@ISR_166), $08, ISR_RING_0);
    IDT.set_gate(167, uint32(@ISR_167), $08, ISR_RING_0);
    IDT.set_gate(168, uint32(@ISR_168), $08, ISR_RING_0);
    IDT.set_gate(169, uint32(@ISR_169), $08, ISR_RING_0);
    IDT.set_gate(170, uint32(@ISR_170), $08, ISR_RING_0);
    IDT.set_gate(171, uint32(@ISR_171), $08, ISR_RING_0);
    IDT.set_gate(172, uint32(@ISR_172), $08, ISR_RING_0);
    IDT.set_gate(173, uint32(@ISR_173), $08, ISR_RING_0);
    IDT.set_gate(174, uint32(@ISR_174), $08, ISR_RING_0);
    IDT.set_gate(175, uint32(@ISR_175), $08, ISR_RING_0);
    IDT.set_gate(176, uint32(@ISR_176), $08, ISR_RING_0);
    IDT.set_gate(177, uint32(@ISR_177), $08, ISR_RING_0);
    IDT.set_gate(178, uint32(@ISR_178), $08, ISR_RING_0);
    IDT.set_gate(179, uint32(@ISR_179), $08, ISR_RING_0);
    IDT.set_gate(180, uint32(@ISR_180), $08, ISR_RING_0);
    IDT.set_gate(181, uint32(@ISR_181), $08, ISR_RING_0);
    IDT.set_gate(182, uint32(@ISR_182), $08, ISR_RING_0);
    IDT.set_gate(183, uint32(@ISR_183), $08, ISR_RING_0);
    IDT.set_gate(184, uint32(@ISR_184), $08, ISR_RING_0);
    IDT.set_gate(185, uint32(@ISR_185), $08, ISR_RING_0);
    IDT.set_gate(186, uint32(@ISR_186), $08, ISR_RING_0);
    IDT.set_gate(187, uint32(@ISR_187), $08, ISR_RING_0);
    IDT.set_gate(188, uint32(@ISR_188), $08, ISR_RING_0);
    IDT.set_gate(189, uint32(@ISR_189), $08, ISR_RING_0);
    IDT.set_gate(190, uint32(@ISR_190), $08, ISR_RING_0);
    IDT.set_gate(191, uint32(@ISR_191), $08, ISR_RING_0);
    IDT.set_gate(192, uint32(@ISR_192), $08, ISR_RING_0);
    IDT.set_gate(193, uint32(@ISR_193), $08, ISR_RING_0);
    IDT.set_gate(194, uint32(@ISR_194), $08, ISR_RING_0);
    IDT.set_gate(195, uint32(@ISR_195), $08, ISR_RING_0);
    IDT.set_gate(196, uint32(@ISR_196), $08, ISR_RING_0);
    IDT.set_gate(197, uint32(@ISR_197), $08, ISR_RING_0);
    IDT.set_gate(198, uint32(@ISR_198), $08, ISR_RING_0);
    IDT.set_gate(199, uint32(@ISR_199), $08, ISR_RING_0);
    IDT.set_gate(200, uint32(@ISR_200), $08, ISR_RING_0);
    IDT.set_gate(201, uint32(@ISR_201), $08, ISR_RING_0);
    IDT.set_gate(202, uint32(@ISR_202), $08, ISR_RING_0);
    IDT.set_gate(203, uint32(@ISR_203), $08, ISR_RING_0);
    IDT.set_gate(204, uint32(@ISR_204), $08, ISR_RING_0);
    IDT.set_gate(205, uint32(@ISR_205), $08, ISR_RING_0);
    IDT.set_gate(206, uint32(@ISR_206), $08, ISR_RING_0);
    IDT.set_gate(207, uint32(@ISR_207), $08, ISR_RING_0);
    IDT.set_gate(208, uint32(@ISR_208), $08, ISR_RING_0);
    IDT.set_gate(209, uint32(@ISR_209), $08, ISR_RING_0);
    IDT.set_gate(210, uint32(@ISR_210), $08, ISR_RING_0);
    IDT.set_gate(211, uint32(@ISR_211), $08, ISR_RING_0);
    IDT.set_gate(212, uint32(@ISR_212), $08, ISR_RING_0);
    IDT.set_gate(213, uint32(@ISR_213), $08, ISR_RING_0);
    IDT.set_gate(214, uint32(@ISR_214), $08, ISR_RING_0);
    IDT.set_gate(215, uint32(@ISR_215), $08, ISR_RING_0);
    IDT.set_gate(216, uint32(@ISR_216), $08, ISR_RING_0);
    IDT.set_gate(217, uint32(@ISR_217), $08, ISR_RING_0);
    IDT.set_gate(218, uint32(@ISR_218), $08, ISR_RING_0);
    IDT.set_gate(219, uint32(@ISR_219), $08, ISR_RING_0);
    IDT.set_gate(220, uint32(@ISR_220), $08, ISR_RING_0);
    IDT.set_gate(221, uint32(@ISR_221), $08, ISR_RING_0);
    IDT.set_gate(222, uint32(@ISR_222), $08, ISR_RING_0);
    IDT.set_gate(223, uint32(@ISR_223), $08, ISR_RING_0);
    IDT.set_gate(224, uint32(@ISR_224), $08, ISR_RING_0);
    IDT.set_gate(225, uint32(@ISR_225), $08, ISR_RING_0);
    IDT.set_gate(226, uint32(@ISR_226), $08, ISR_RING_0);
    IDT.set_gate(227, uint32(@ISR_227), $08, ISR_RING_0);
    IDT.set_gate(228, uint32(@ISR_228), $08, ISR_RING_0);
    IDT.set_gate(229, uint32(@ISR_229), $08, ISR_RING_0);
    IDT.set_gate(230, uint32(@ISR_230), $08, ISR_RING_0);
    IDT.set_gate(231, uint32(@ISR_231), $08, ISR_RING_0);
    IDT.set_gate(232, uint32(@ISR_232), $08, ISR_RING_0);
    IDT.set_gate(233, uint32(@ISR_233), $08, ISR_RING_0);
    IDT.set_gate(234, uint32(@ISR_234), $08, ISR_RING_0);
    IDT.set_gate(235, uint32(@ISR_235), $08, ISR_RING_0);
    IDT.set_gate(236, uint32(@ISR_236), $08, ISR_RING_0);
    IDT.set_gate(237, uint32(@ISR_237), $08, ISR_RING_0);
    IDT.set_gate(238, uint32(@ISR_238), $08, ISR_RING_0);
    IDT.set_gate(239, uint32(@ISR_239), $08, ISR_RING_0);
    IDT.set_gate(240, uint32(@ISR_240), $08, ISR_RING_0);
    IDT.set_gate(241, uint32(@ISR_241), $08, ISR_RING_0);
    IDT.set_gate(242, uint32(@ISR_242), $08, ISR_RING_0);
    IDT.set_gate(243, uint32(@ISR_243), $08, ISR_RING_0);
    IDT.set_gate(244, uint32(@ISR_244), $08, ISR_RING_0);
    IDT.set_gate(245, uint32(@ISR_245), $08, ISR_RING_0);
    IDT.set_gate(246, uint32(@ISR_246), $08, ISR_RING_0);
    IDT.set_gate(247, uint32(@ISR_247), $08, ISR_RING_0);
    IDT.set_gate(248, uint32(@ISR_248), $08, ISR_RING_0);
    IDT.set_gate(249, uint32(@ISR_249), $08, ISR_RING_0);
    IDT.set_gate(250, uint32(@ISR_250), $08, ISR_RING_0);
    IDT.set_gate(251, uint32(@ISR_251), $08, ISR_RING_0);
    IDT.set_gate(252, uint32(@ISR_252), $08, ISR_RING_0);
    IDT.set_gate(253, uint32(@ISR_253), $08, ISR_RING_0);
    IDT.set_gate(254, uint32(@ISR_254), $08, ISR_RING_0);
    IDT.set_gate(255, uint32(@ISR_255), $08, ISR_RING_0);
end;

end.