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
	Include->Color - Provides types relating to color/graphics.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit color;

interface

type
    TRGB32 = bitpacked record
        B : uint8;
        G : uint8;
        R : uint8;
        A : uint8;
    end;

    TRGB24 = bitpacked record
        B : uint8;
        G : uint8;
        R : uint8;
    end;

    TRGB16 = bitpacked record
        B : UBit5;
        G : UBit6;
        R : UBit5;
    end;

    TRGB8 = bitpacked record
        B : UBit2;
        G : UBit4;
        R : UBit2;
    end;

const
    black : TRGB32 = (B: 000; G: 000; R: 000; A: 000);
    white : TRGB32 = (B: 255; G: 255; R: 255; A: 000);
    red   : TRGB32 = (B: 000; G: 000; R: 255; A: 000);
    green : TRGB32 = (B: 000; G: 255; R: 000; A: 000);
    blue  : TRGB32 = (B: 255; G: 000; R: 000; A: 000);

implementation

end.