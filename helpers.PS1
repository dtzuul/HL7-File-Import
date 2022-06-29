#MIT License  - Copyright (c) 2022 Dan M
#set of utility functions

#init work_area temporarly for current runnig directory just in case we need to do logging before a work area is defined. 
#The calling script can properly set the work area later on
$work_area = "."
#write a message to a log file and to console
#messages are prefixed with the current date and time
function writeToLogFile ([string]$message)
{
    
    #define the log file path, every day a new log will be created
    #do not cach it in a variable to allow path change based on $work_area as needed 
    $todaysdate=Get-Date -Format "yyyy-MM-dd"
    $logfilepath = Join-Path -Path $work_area -ChildPath $($todaysdate+".log")
    
    $towrite = (Get-Date).ToString() + " - " +  $message
    $towrite >> $logfilepath
    Write-Host $towrite
}
#write an message from an exception handler to the log (and console)
#message is prefixed with [ERROR] and appended with the exception detail and stack trace
function writeExceptionToLogFile ([string]$message)
{
    writeToLogFile ("[ERROR] " + $message + ". Reason: " + $PSItem + " Stack: " + $PSItem.ScriptStackTrace)
}

function createFolderAsNeeded([string]$path) {

    if (!$(Test-Path $path)) {
        New-Item $path -ItemType Directory
        $message = "$path created successfully"
        writeToLogFile $message
    }
}

#given a string and a regex pattern extracting matches and captures into an array, returns the value at the "pos" index in that array
function extractToken([string]$source, [string]$pattern, [int]$pos)
{
    #notice usage of "groups" to allow for captures extraction
    [array]$values = Select-String $pattern -InputObject $source -AllMatches | ForEach-Object {$_.matches.Groups.Value}
    if ($values.Length -ge $pos) {
        return $values[$pos]
    }
    return $null
}

#HL7 message encapsulating 
function embedInMLLPEnvelope([string]$message) 
{
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(0x0B -as [char])
    [void]$sb.Append($message)
    [void]$sb.Append(0x1C -as [char])
    [void]$sb.Append(0x0D -as [char])
    return $sb.ToString()
}

#extract message string form HL7 MLLP envelope
function removeMLLPEnvelope([string]$message)
{
    [int]$start = $message.IndexOf(0x0B -as [char])
    [int]$end = $message.IndexOf(0x1C -as [char])
    [string]$ackString = $message.Substring($start + 1, $end - 1)
    $option = [System.StringSplitOptions]::RemoveEmptyEntries
    [array]$ackLines = $ackString.Split(0x0D -as [char], $option);
    return $ackLines
}

#log HL7 ack messages. If an error message is returned, then also output the whole MSA segment
function writeHl7AckToLogFile([array] $ackLines)
{
    $message = "ACK received - "
    foreach ($segment in $ackLines)
    {
        #find the right segment (MSA)
        if($segment.StartsWith("MSA"))
        {
            [array]$msaFields = $segment.Split('|')
            if($msaFields.Length -gt 1){
                $ackStatus = $msaFields[1]
                if($ackStatus -eq "AA")
                {
                    $message = $message + "[Positive acknowledgment]"
                }
                elseif($ackStatus -eq "AE")
                {
                    $message = $message + "[Application error] :" + $segment
                }
                elseif($ackStatus -eq "AR")
                {
                    $message = $message + "[Application reject] :" + $segment
                }
            }
        }
    }
    writeToLogFile $message
}
# encapsulates an HL7 messge as MLLP frame, send it to the HL7 server and (optionally) waits for Ack
function sendHL7Message([string]$desthost, [int]$port, [string]$message, [string] $encodingText, [bool]$useSSL, $SSLProtocol, [bool]$waitForAck)
{
    try
    {
        #HL7 messages are in an MLLP envelope
        $mllpMessage = embedInMLLPEnvelope $message
        #use the right encoding (UTF-8 usually)
        $encoding = [System.Text.Encoding]::GetEncoding($encodingText)
        $buffer = $encoding.GetBytes($mllpMessage)

        #setup the TCP channel
        $tcpClient  = New-Object System.Net.Sockets.TcpClient
        $tcpClient.SendTimeout = $hl7_server_send_recieve_timeout
        $tcpClient.ReceiveTimeout = $hl7_server_send_recieve_timeout
    
        #actual connection to server
        $tcpClient.Connect($desthost, $port)
        $stream = $null
        if($useSSL){
            #setup SSL
            $currStream = $tcpClient.GetStream( )
            if($hl7_server_accept_any_SSL_certificate) {
                $stream = New-Object  System.Net.Security.SslStream($currStream, $false, {$true})
            } else {
                $stream = New-Object  System.Net.Security.SslStream($currStream, $false)
            }
    
            
            #hopefully the server's certificate is accepted 
            if($SSLProtocol -eq -1){
                $stream.AuthenticateAsClient($hl7_server_SSL_TargetHost)
            }
            else {
                $stream.AuthenticateAsClient($hl7_server_SSL_TargetHost, $null, $SSLProtocol, $false);
            }
        }
        else
        {
            $stream = $tcpClient.GetStream( )
        }
        #send data
        $stream.Write($buffer, 0, $buffer.Length);
		$stream.Flush()
        writeToLogFile ("Sent HL7 message to $desthost on port $port with length " + $buffer.Length)

        [array]$ackLines = $null
        if($waitForAck){
            writeToLogFile "Waiting for ACK"
            #assume no ack longer than 4096
            $responseBuffer = New-Object System.Byte[] 4096
            $responseLen = $stream.Read($responseBuffer, 0, $responseBuffer.Length)
            $ack = $encoding.GetString($responseBuffer, 0, $responseLen)
            #extract the message from envelope
            $ackLines = removeMLLPEnvelope $ack
            #output details
            writeHl7AckToLogFile $ackLines
        }
        return $ackLines;
        
    }
    catch
    {
        writeExceptionToLogFile ("Sending HL7 message to $desthost on port $port failed")
    }
    finally
    {
        if($stream) { $stream.Close()}
        if($tcpClient) { $tcpClient.Close()}
    } 
}

#for each entry in a list of regex "mappings" ({marker, regex, matches/captures index} extract the value from the given string 
#and fill for return an hash {marker, value}
function extractTokens([string]$source, [array]$mappings, [hashtable]$replace_hash)
{
    foreach ($mapping in $mappings)
    {
        $result = extractToken $source $mapping.Regex $mapping.MatchPos
        $replace_hash[$mapping.HL7TemplateMarker] = $result
    }
}
#simple utilty to check if all the values in a hash are filled in 
function checkHashForMissingValuesThrowException([hashtable]$replace_hash)
{
    foreach ($key in $replace_hash.Keys) {
        $keyVal =  $($replace_hash[$key])
        if(!($keyVal))
        {
            throw "No match for " + $key;
        }
        if($keyVal.Length -eq 0)
        {
            throw "Empty match for " + $key;
        }
    }
}

#simple file content as base64 
function fileAsBase64([string]$file)
{
    $contentbase64 = [convert]::ToBase64String((Get-Content -path $file -Encoding byte))
    return $contentbase64
}
#for each key-value pair in an hash, replace in the given string template any occurence of the "key" with the "value"
function replaceInTemplate([hashtable]$hash, [string]$template){

    Foreach ($key in $hash.Keys) {
        $template = $template.Replace($key, $hash.$key)
     }
     return $template;
}