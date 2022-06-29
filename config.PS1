#MIT License  - Copyright (c) 2022 Dan M
#config file for import.PS1

########################
# Monitoring config
########################

#script will look for incoming files in this location. Running user should be allowed to read and move files out of this location. It is usually a network path.
$drop_folder = "C:\HL7Import\Drop\"
#but only at files matching this pattern
$file_pattern = "*.pdf"

#script will move PDFs in this Root workarea. Running user should have full read/write/delete access 
#do not use a root work area inside the drop folder - the search for PDFs in the drop folder is recursive and will collide with already processed PDFs in the work area 
#this can be a local system folder. Just in case it is a network folder, to allow High Availability separation, the script will use internally the running system's hostname as a working area
$root_work_area = "C:\HL7Import\Work\"

#the HL7 template, the script will replace markers with runtime content extracted from the filename, full filename, file content etc  
$hl7_template_path = "C:\HL7Import\Script\mdm_t02.template"

########################
# Extraction patterns
########################

#define the extraction patterns from filename. 
#the script will use  .Net based Regex against the filename, use the MatchPos to pick a particualar match index, then replace the HL7TemplateMarker string with the extracted value 
#all defined mappings are mandatory, if no match or empty string, no HL& message will be generated 
#in this example, the regex extracts all strings between _ (underscores) as matches and picks the second match to replace the {MRN} marker in the template.  
#one should confirm the regex directly in the powershell console by running the command: Select-String "regex_pattern" -InputObject "string_to_evaluate" -AllMatches | ForEach-Object {$_.matches.Groups.Value}
$mappings_filename = @(
    [pscustomobject]@{HL7TemplateMarker="{MRN}";Regex="[^_]+";MatchPos=1}
)
#same as above, but look at fullpath (just in case some string from the Fullpath needs to make it in the HL7 message )
$mappings_fullpath = @(
    #[pscustomobject]@{HL7TemplateMarker="{PATH_PART}";Regex="([^\\]+)";MatchPos=3}
)

#same as above, but look at filecontent (just in case some string from the file content needs to make it in the HL7 message )
$mappings_filecontent = @(
    #[pscustomobject]@{HL7TemplateMarker="{PRODUCER}";Regex="Producer\((.*?)\)";MatchPos=0}
)
#hl7 template marker name for base64 content.  
$mapping_base64FileContent = "{BASE64_CONTENT}"

########################
# destination HL7 server
########################
$hl7_server = "127.0.0.1"
# destination port
$hl7_server_port = 6661
#SSL section
$hl7_server_useSSL = $false
#SSL protocol: -1 : use windows default. Else, any of these values:. None = 0x0, Ssl2 = 0xC, Ssl3 = 0x30, Tls = 0xC0, (deprecated)Default = 0xF0, Tls11 = 0x300, Tls12 = 0xC00, Tls13 = 0x3000
$hl7_server_SSL_protocol = -1
#allow accepting any certificate in SSL mode
$hl7_server_accept_any_SSL_certificate = $false
#target hostname - shoud match server's certificate
$hl7_server_SSL_TargetHost = "localhost"
#message encoding
$hl7_server_encoding = "UTF-8"
#should wait for ack
$hl7_server_waitForAck = $true
#tcp timeout miliseconds
$hl7_server_send_recieve_timeout = 10000
#just in case a delay is needed between sending messages
$hl7_delay_between_message_ms = 0
