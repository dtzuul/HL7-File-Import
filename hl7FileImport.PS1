#MIT License  - Copyright (c) 2022 Dan M

#Monitors a drop folder for (PDF) files and send them to an HL7 server based on a template
#The template contains markers (dynamic parameters) which can be inferred from the filename, file path or file content using regex 
#one can set up a scheduled task in windows to run this powershell script regularly
#see config is in config.PS1

# import config 
. "./config.PS1"

#now import utility functions
. "./helpers.PS1"

#some minor checks
if (!$(Test-Path $hl7_template_path)) {
    $message = "HL7 template [$hl7_template_path] does not exist"
    writeToLogFile $message
    Return
}
if (!$(Test-Path $drop_folder)) {
    $message = "Drop folder [$drop_folder] does not exist"
    writeToLogFile $message
    Return
}

if (!$(Test-Path $root_work_area)) {
    $message = "Root Work area [$root_work_area] does not exist"
    writeToLogFile $message
    Return
}

#to allow for network path usage as "work area" in an HA deployment scenario, use the hostname as actual work area. This allows multiple hosts to run this script in parallel
$work_area = Join-Path -Path $root_work_area -ChildPath $env:computername
#"processed" folder will contain the source pdf once the hl7 message is created out of it
$work_area_processing = Join-Path -Path $work_area -ChildPath "processing"
#"processed" folder will contain the source pdf once the hl7 message is created out of it
$work_area_processed = Join-Path -Path $work_area -ChildPath "processed"
#hl7 folder will contain hl7 messages cereated out of PDF
$work_area_hl7 = Join-Path -Path $work_area -ChildPath "hl7"

#prepare as needed work area
createFolderAsNeeded $work_area
createFolderAsNeeded $work_area_processing
createFolderAsNeeded $work_area_hl7
createFolderAsNeeded $work_area_processed

####################################################
# 1. look for PDF files to take ownership for processing
####################################################

[array]$incoming_files = @(Get-ChildItem -Path $drop_folder -Recurse -Filter $file_pattern)
if($incoming_files.Length -eq 0) {
    writeToLogFile "No new files dropped"
    #will still continue to process anyhting else (just in case script failed midway or any other reasons)
}

foreach ($fileIncoming in $incoming_files)
{
    try {
        #take ownership for processing
        #may have errors: another host may want to move it as the same time or, more likley, the file is still beeing written to this location 
        Move-Item -Path $fileIncoming.FullName -Destination $work_area_processing
        writeToLogFile ("Collected [" + $fileIncoming.Name + "] for processing")

    } catch{
        writeExceptionToLogFile ("Attempt to move for processing [" + $fileIncoming.Name + "] failed. It may be a normal read-write timing error, will try again next round")
    }
}

##################################
# 2. look for PDF files for processing and Create Hl7 message on disk out of pdf based on a template
##################################

#note that it is safe to process "pending folder" files as there can be only one script running at a time on a host under scheduled tasks
[array]$pending_files = @(Get-ChildItem -Path $work_area_processing -Recurse -Filter $file_pattern)
if($pending_files.Length -eq 0) {
    writeToLogFile "No pending files for HL7 message creation"
    #will still continue to process anyhting else (just in case script failed midway or any other reasons)
}

#define the replacing mapping hash
$replaceHash = @{}

foreach ($file in $pending_files)
{
    $shouldMoveToProcessed = $true
    try {
        
        #extract mappings from filename
        if($mappings_filename.count -ge 0) {
            extractTokens $file.Name $mappings_filename $replaceHash
        }
        #extract mappings from filename
        if($mappings_fullpath.count -ge 0) {
            extractTokens $file.FullName $mappings_fullpath $replaceHash
        }
        #extract mappings from filecontent
        if($mappings_fullpath.count -ge 0 ) {
            $file_content_raw = Get-Content -path $file.FullName -Raw
            extractTokens $file_content_raw $mappings_filecontent $replaceHash
        }
        if($mapping_base64FileContent.Length -gt 0)
        {
            #get the file as base64
            $base64Content = fileAsBase64 $file.FullName
            $replaceHash[$mapping_base64FileContent] = $base64Content
        }
        #validate that we are ok for replace. If a marker is not found an exception will be thrown  
        checkHashForMissingValuesThrowException $replaceHash
       
        #read hl7 template
        $templateContent = Get-Content -path $hl7_template_path -Raw

        #obtain an in memory hl7 message by replacing the variables with actual values
        $hl7Content = replaceInTemplate $replaceHash $templateContent

        #write hl7 content as a file
        $hl7filepath = Join-Path -Path $work_area_hl7 -ChildPath ($file.Name + ".hl7")
        if (Test-Path $hl7filepath) {
            writeToLogFile ("File [" + $hl7filepath + "] already exists (same filename and not sent yet?) , trying again later")
            $shouldMoveToProcessed = $false
            continue
        }
        $hl7Content >> $hl7filepath
        writeToLogFile ("Created HL7 message in [" + $hl7filepath + "]")
    } catch{
        writeExceptionToLogFile ("Attempts to make hl7 out of " + $file + " failed")
    }
    finally {
        #move the file to processed, regardless if succeeded to make HL7 out of it or not (no reason to try again if failed in the first place)
        #except if hl7 creation is blocked - then skip moving it until the hl7 is sent 
        if($shouldMoveToProcessed) 
        {
            #check if file already exists (somebody dropping the same name over and over?)
            $destFullFilename = Join-Path -Path $work_area_processed -ChildPath $file.Name
            if (Test-Path $destFullFilename) {
                writeToLogFile ("File [" + $file.Name  + "] already exists in [$work_area_processed], overwriting")
            }
            Move-Item -Path $file.FullName -Destination $work_area_processed -Force
            writeToLogFile ("File [" + $file.FullName + "] moved to Processed")
        }   

    }
}


##############################################################
# 3. send HL7 
##############################################################

[array]$to_be_sent_files = @(Get-ChildItem -Path $work_area_hl7 -Recurse -Filter "*.hl7")
if($to_be_sent_files.Length -eq 0) {
    writeToLogFile "No hl7 files to send, exiting"
    Return
}


foreach ($file in $to_be_sent_files)
{
    try {
        writeToLogFile "Sending $file to HL7 server"
        $message = Get-Content -path $file.FullName -Raw
        $ackLines = sendHL7Message $hl7_server $hl7_server_port $message $hl7_server_encoding $hl7_server_useSSL $hl7_server_SSL_protocol $hl7_server_waitForAck
        $canDelete = $true
        if($hl7_server_waitForAck -and  ($null -eq $ackLines))
        {
            #server did not sent ack but it was supposed to
            $canDelete = $false
        }
        if($canDelete){
            Remove-Item -Path $file.FullName
        }

        if($hl7_delay_between_message_ms -gt 0){
            start-sleep -Milliseconds $hl7_delay_between_message_ms
        }
    } catch{
        writeExceptionToLogFile ("Sending hl7 [" + $file + "] to server [" + $server + "] port [" + $hl7_server_port + "] SSL : " + $hl7_server_useSSL + " failed")
    }
}




