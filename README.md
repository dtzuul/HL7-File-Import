# HL7 File Import

'HL7 File Import' is a PowerShell script which can be used to send files in a Drop folder to an HL7 server.
The files are embedded as base64 into an HL7 message, based on a provided template with dynamic parameters (replace markers).
It performs the following steps for each dropped file:
- creates an HL7 message by replacing each marker in the HL7 template with the value obtained using an regex expression
- sends the created HL7 message to an HL7 server

## Features
- runnable in any PowerShell compatible environment
- can be executed periodically for automatic "folder monitoring" using a scheduled task on windows or cron jobs on Linux
- allows setting up regex extraction from filename, file path or file content to replace any HL7 segment field
- can send to SSL enabled HL7 servers
- designed to have multiple instances running on different systems monitoring the same "drop folder" network path to allow high availability deployments
- full logging 

## Deployment

- Deploy the scripts in any folder
- Create an HL7 message template (see also sample MDM T02)
- modify the configuration file ```Config.PS1``` to match the environment

## Initial validation and troubleshooting

- drop a file in the Drop folder
- open PowerShell 
- change directory to script location 
- and run and manually run the main script (type-in ```.\hl7FileImport.PS1```)
- validate that the HL7 server receives the message 
- troubleshoot using provided console output and log file created in the root work directory

## 'Scheduled tasks' deployment (Windows)

- Create new task in task scheduler, set to 'run whether user is logged on or not'
- define the running user. Typically, it is a domain account with access to the drop location
- Trigger: on a schedule, every X minutes, run indefinitely
- Actions: Run a program ```C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe``` with Arguments ```-File <DEPLOY_PATH>\hl7FileImport.PS1``` and Start-in ```<DEPLOY_PATH>```
- Optionally enable Scheduled tasks history for future troubleshooting

## License
MIT