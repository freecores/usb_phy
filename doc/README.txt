
USB 1.1 PHY
==========

Status
------
This core is done. It was tested with a USB 1.1 core I have written on
a XESS XCV800 board with a a Philips PDIUSBP11A transceiver.
I have NOT yet tested it with my USB 2.0 Function IP core.

Test Bench
----------
There is no test bench, period !
Please don't email me asking for one, unless you want to hire me to
write one ! As I said above I have tested this core in real hardware and
it works just fine.

Documentation
-------------
Sorry, there is none. I just don't have the time to write it. I have tried
to follow the UTMI interface specification from USB 2.0 with one exception:
I have not added any error checking in the RX PHY, hence the RxError pin
is permanently tide to ground.

Misc
----
The USB 1.1 Phy Project Page is:
http://www.opencores.org/cores/usb_phy

To find out more about me (Rudolf Usselmann), please visit:
http://www.asics.ws


Directory Structure
-------------------
[core_root]
 |
 +-doc                        Documentation
 |
 +-bench--+                   Test Bench
 |        +- verilog          Verilog Sources
 |        +-vhdl              VHDL Sources
 |
 +-rtl----+                   Core RTL Sources
 |        +-verilog           Verilog Sources
 |        +-vhdl              VHDL Sources
 |
 +-sim----+
 |        +-rtl_sim---+       Functional verification Directory
 |        |           +-bin   Makefiles/Run Scripts
 |        |           +-run   Working Directory
 |        |
 |        +-gate_sim--+       Functional & Timing Gate Level
 |                    |       Verification Directory
 |                    +-bin   Makefiles/Run Scripts
 |                    +-run   Working Directory
 |
 +-lint--+                    Lint Directory Tree
 |       +-bin                Makefiles/Run Scripts
 |       +-run                Working Directory
 |       +-log                Linter log & result files
 |
 +-syn---+                    Synthesis Directory Tree
 |       +-bin                Synthesis Scripts
 |       +-run                Working Directory
 |       +-log                Synthesis log files
 |       +-out                Synthesis Output
