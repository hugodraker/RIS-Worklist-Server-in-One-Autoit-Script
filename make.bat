c:\masm32\bin\ml /c /coff /Cp pacs-server01.asm
c:\masm32\bin\link /subsystem:windows pacs-server01.obj
c:\masm32\bin\ml /c /coff /Cp worklist-server01.asm
c:\masm32\bin\link /subsystem:windows worklist-server01.obj
c:\masm32\bin\ml /c /coff /Cp PACS-MANAGER.asm
c:\masm32\bin\link /subsystem:windows PACS-MANAGER.obj
@rem pacs-server01.exe