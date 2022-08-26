Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Write-host "Hello world"
<# ------------------   Tachyon Instructions Read/Write script -----------------------------------------------------
# (c) DXC Technology (2022)
# ------------------------------------------------------------------------------------------------------------------

# Tachyon Instructions Pipeline script
# Version 1.0
# Developed by MDM Engineering Team -------

#This script reads the add-on Instructions repository, fetches the instructions from the Instructions files and Inserts them to a database.
#Script is initiated by Tachyon Instructions Pipeline


#function to read folder and files recursively
function ReadAllFolders
{
    Param
    (
        [String]$path
    )

    try
    {
        #$path = 'D:\WDS\PLTest\'
        [String]$FirstcheckEntryFlag
        #$ScriptPath = Split-Path $path
        $ScriptPath =  $path

        Write-Log "Script Path $ScriptPath"

        $FirstcheckEntryFlag = 0

        $DirsInScriptPath = (Get-Item -Path $ScriptPath).GetDirectories()

        foreach ($dir in $DirsInScriptPath)
        {
            Write-Log "Directory $dir"

            if ($dir.ToString() -ne "TachyonPipelineLibrary")
            {
                $InstructionsPath = $ScriptPath.ToString() + "\$dir"
            }
        }

        if ((Test-Path -Path $InstructionsPath) -eq $false)
        {
            Write-Log "Invalid path detected. Please check the path instructions and try again" 2
            Exit
        }

        Write-Log "Reading Instruction from $InstructionsPath" 1

        function getAllFile([string]$InstructionsPath)
        {
            $fc = new-object -com scripting.filesystemobject
            $folder = $fc.getfolder($InstructionsPath)

            foreach ($i in $folder.files)
            {
                if (($i.Name -ne "Manifest.xml") -and ($i.Name.EndsWith(".xml")))
                {
                        #$mydllPath = GetInstFolderSubPath -folderPath $InstructionsPath

                        #Check if we are running the pipeline for the first time. If yes, insert xml information into database. If not, then continue regular process
                        $FirstRunFlag = CheckIfFirstRun -mydllPath $path -myPath $InstructionsPath
                        if (($FirstRunFlag -eq $true) -and ($FirstcheckEntryFlag -eq 0))
                        {
                            $filePath = $folder.Path + '\' + $i.Name

                            $SubFolderName = GetInstFolderSubPath -subFolderName $folder.Path -folderPath $filePath

                            ReadXMLAndInsertIfFirstTime -subFolderName $subFolderName -filePath $filePath -Path $path


                        }
                        else
                        {
                            Write-Log "Reading properties of file $($i.Path)" 1

                            $ModifiedDate = $i.DateLastModified

                            #if the file has been changed in the last 24 hours
                            if ((($ModifiedDate -gt $(Get-Date).AddDays(-1))))
                            {

                                #Open the XML file and read the XML attributes
                                try
                                {
                                    $filePath = $folder.Path + '\' + $i.Name

                                    $SubFolderName = GetInstFolderSubPath $folder.Path

                                    # ----------- Read XML file --------------------
                                    [XML]$xmlfile = Get-Content $filePath

                                    if ($xmlfile)
                                    {
                                        # ------------- Get Instructions Attributes --------------------------
                                        $myInstID = $xmlfile.InstructionDefinition.InstructionID
                                        $myInstName = $SubFolderName + ' '+ $xmlfile.InstructionDefinition.Name
                                        $myInstReadablePayload = $xmlfile.InstructionDefinition.ReadablePayload
                                        $myInstDescription = $xmlfile.InstructionDefinition.Description
                                        $myInstType = $xmlfile.InstructionDefinition.InstructionType
                                        $myInstTtlMinutes = $xmlfile.InstructionDefinition.InstructionTtlMinutes
                                        $myInstResponseTtlMinutes = $xmlfile.InstructionDefinition.ResponseTtlMinutes
                                        $myInstVersion = $xmlfile.InstructionDefinition.Version
                                        $myInstAuthor = $xmlfile.InstructionDefinition.Author
                                        $myInstPayload = $xmlfile.InstructionDefinition.Payload.InnerXml
                                        $myInstComments = $xmlfile.InstructionDefinition.Comments
                                        $myInstSchemaJson = $xmlfile.InstructionDefinition.SchemaJson.InnerXml
                                        $myInstTaskGroups = $xmlfile.InstructionDefinition.TaskGroups.InnerXml
                                        $myInstAggregationJson = $xmlfile.InstructionDefinition.AggregationJson
                                        $mySignature = $xmlfile.InstructionDefinition.Signature.InnerXml
                                        #------------------------------------------------------------------------

                                        #----Read the existing instructions from the database -------------------
                                        #[Reflection.Assembly]::LoadFile("D:\WDS\PLTest\System.Data.SQLite.dll")
                                        if (-not $path.Contains("TachyonPipelineLibrary"))
                                        {
                                            $Repeatpath = $path + "\TachyonPipelineLibrary"
                                        }
                                        [Reflection.Assembly]::LoadFile($Repeatpath + "\System.Data.SQLite.dll")

                                        #$sDatabasePath="D:\WDS\PLTest\TachyonInstructions.db"
                                        $sDatabasePath = $Repeatpath + "\TachyonInstructions.db"

                                        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
                                        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
                                        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
                                        $oSQLiteDBConnection.open()



                                        $oSQLiteDBCommand = $oSQLiteDBConnection.CreateCommand()
                                        $oSQLiteDBCommand.Commandtext = "SELECT * FROM Instructions"

                                        $adapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $oSQLiteDBCommand
                                        $data = New-Object System.Data.DataSet
                                        [void]$adapter.Fill($data)

                                        #Check if our dataset has any records
                                        if ($data.Tables[0].Rows.Count -gt 0)
                                        {
                                            #Set the row counter to 0. This counter will be used to count the rows that did not meet the match condition
                                            $rowcount = 0

                                            foreach ($row in $data.Tables[0].Rows)
                                            {
                                                if ($row["InstructionName"] -eq $myInstName) #if instruction names match, then we see if there is any other change for the instruction
                                                {
                                                    if (($row["InstructionReadablePayload"] -ne $myInstReadablePayload) -or ($row["InstructionDescription"] -ne $myInstDescription) -or ($row["InstructionType"] -ne $myInstType) -or ($row["InstructionTtlMinutes"] -ne $myInstTtlMinutes) -or ($row["InstructionResponseTtlMinutes"] -ne $myInstResponseTtlMinutes) -or ($row["InstructionVersion"] -ne $myInstVersion) -or ($row["InstructionAuthor"] -ne $myInstAuthor) -or ($row["InstructionPayload"] -ne $myInstPayload) -or ([String]::IsNullOrEmpty($row["InstructionComments"]) -ne [String]::IsNullOrEmpty($myInstComments)) -or ($row["InstructionSchemaJson"] -ne $myInstSchemaJson) -or ($row["InstructionTaskGroups"] -ne $myInstTaskGroups) -or ($row["InstructionAggregateJson"] -ne $myInstAggregationJson) -or ($row["InstructionSignature"] -ne $mySignature))
                                                    {
                                                        #Update
                                                        UpdateInstructionsInSQL -InstID $row["InstructionID"] -InstName $myInstName -InstReadPayLoad $myInstReadablePayload -InstDesc $myInstDescription -InstType $myInstType -InstTtlMin $myInstTtlMinutes -InstTtlRespMin $myInstResponseTtlMinutes -InstVer $myInstVersion -InstAuth $myInstAuthor -InstPayload $myInstPayload -InstComments $myInstComments -InstSchemaJson $myInstSchemaJson -InstTaskGroups $myInstTaskGroups -InstAggrJson $myInstAggregationJson -InstSign $mySignature -PathOfSQLDll $Path -Connection $oSQLiteDBConnection
                                                        Write-Log "Updated $myInstName in database." 1
                                                    }


                                                }

                                                elseif ($row["InstructionName"] -ne $myInstName)
                                                {
                                                    #Increment this counter only when it doesn't match with any name in the database
                                                    $rowcount = $rowcount + 1
                                                }

                                            }

                                            #Now, if the XML file data is not in the database, the count will be equal. So go ahead and insert the record into the database.
                                            if ($rowcount -eq $data.Tables[0].Rows.Count)
                                            {
                                                #Insert new record into database as the instruction name is not found in the list
                                                InsertInstructionIntoSQL -InstName $myInstName -InstReadPayLoad $myInstReadablePayload -InstDesc $myInstDescription -InstType $myInstType -InstTtlMin $myInstTtlMinutes -InstTtlRespMin $myInstResponseTtlMinutes -InstVer $myInstVersion -InstAuth $myInstAuthor -InstPayload $myInstPayload -InstComments $myInstComments -InstSchemaJson $myInstSchemaJson -InstTaskGroups $myInstTaskGroups -InstAggrJson $myInstAggregationJson -InstSign $mySignature -PathOfSQLDll $Path -Connection $oSQLiteDBConnection
                                                Write-Log "Captured $myInstName Instruction into database." 1
                                            }

                                        }
                                        else  #This means that database doesn't contain any records. We will go ahead and insert what we found in the XML file.
                                        {
                                            InsertInstructionIntoSQL -InstName $myInstName -InstReadPayLoad $myInstReadablePayload -InstDesc $myInstDescription -InstType $myInstType -InstTtlMin $myInstTtlMinutes -InstTtlRespMin $myInstResponseTtlMinutes -InstVer $myInstVersion -InstAuth $myInstAuthor -InstPayload $myInstPayload -InstComments $myInstComments -InstSchemaJson $myInstSchemaJson -InstTaskGroups $myInstTaskGroups -InstAggrJson $myInstAggregationJson -InstSign $mySignature -PathOfSQLDll $Path -Connection $oSQLiteDBConnection
                                            Write-Log "Captured $myInstName Instruction into database." 1
                                            # Log record inserted message
                                        }

                                    }
                                    else
                                    {
                                        #Log message that XML file is blank or attributes could not be obtained
                                    }


                                }
                                catch
                                {
                                    # Error reading XML file. Update log accordingly
                                    Write-Log "Failed to read the XML file $i.Name from folder $folder. Critical error -> Error: $($_.Exception.Message)" 3
                                }
                            }

                        }

                    }

                    #Write-Host "`nFile Name::" $i.Name
                    #Write-Host "File Path::" $i.Path

            }



            foreach ($i in $folder.subfolders)
            {
                getAllFile($i.path)
            }
        }

        #Iteration for addon pack folder
        getAllFile $InstructionsPath

        $FirstcheckEntryFlag = 1

        #Get rid of blank record
        ClearBlankRecordFromDB -Path $path

        #Upate CheckFirstRecords table and set the field to false.
        UpdateIsFirstField -Path $path
    }
    catch
    {
        Write-Log "Failed to read the folder structure. Critical error -> Error: $($_.Exception.Message)" 3
        #Write-Host "`n Error:: $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Yellow
    }

}

function GetInstFolderSubPath
{
    param
    (
        [String]$folderPath
    )

    try
    {
        $splitPath = $folderPath.Split('\')

        if ($folderPath.Contains(".xml"))
        {
            $lastFolderNo = $splitPath.Count - 2
        }
        else
        {
            $lastFolderNo = $splitPath.Count - 1
        }

        return $splitPath[$lastFolderNo].ToString()
    }
    catch
    {
    }
}

function GetInstFolderSubPath
{
    param
    (
        [String]$subFolderName,
        [String]$folderPath
    )

    try
    {
        $splitPath = $subFolderName.Split('\')

        $lastFolderNo = $splitPath.Count - 1

        return $splitPath[$lastFolderNo].ToString()
    }
    catch
    {
    }
}

function CheckIfFirstRun
{
    param
    (
        [String]$mydllPath,
        [String]$myPath
    )

    [String]$RetValue

    try
    {
        #$myPath = Get-Location
        #$myPath = $myPath.ToString() + "\"

        if (-not $mydllPath.Contains("TachyonPipelineLibrary"))
        {
            $mydllPath = $mydllPath + "\TachyonPipelineLibrary"
        }

        [Reflection.Assembly]::LoadFile($mydllPath.ToString() + "\System.Data.SQLite.dll")
        $sDatabasePath = $mydllPath.ToString() +  "\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
        $oSQLiteDBConnection.open()


        $oSQLiteDBCommand = $oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext = "SELECT IsFirst FROM CheckFirstRecords"
        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $RetValue = $oSQLiteDBCommand.ExecuteScalar()

        $oSQLiteDBConnection.Close()
    }
    catch
    {
        Write-Log "Failed to check IsFirst Instructions. Error: $($_.Exception.Message)" 3
    }

    if ($RetValue -eq 1)
    {
        return $true
    }
    else
    {
        return $false
    }
}

function ClearBlankRecordFromDB
{
    param
    (
        [String]$Path
    )



    try
    {
        if (-not $Path.Contains("TachyonPipelineLibrary"))
        {
            $Path = $Path + "\TachyonPipelineLibrary"
        }

        [Reflection.Assembly]::LoadFile($Path + "\System.Data.SQLite.dll")
        $sDatabasePath = $Path + "\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
        $oSQLiteDBConnection.open()


        $oSQLiteDBCommand = $oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext = "DELETE FROM Instructions WHERE InstructionName = ''"
        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $RetValue = $oSQLiteDBCommand.ExecuteNonQuery()

        $oSQLiteDBConnection.Close()
    }
    catch
    {
        Write-Log "Failed to Clear blank Instruction. Error: $($_.Exception.Message)" 3
    }


}

function UpdateIsFirstField
{
    param
    (
        [String]$Path
    )

    try
    {
        if (-not $Path.Contains("TachyonPipelineLibrary"))
        {
            $Path = $Path + "\TachyonPipelineLibrary"
        }

        [Reflection.Assembly]::LoadFile($Path + "\System.Data.SQLite.dll")
        $sDatabasePath = $Path + "\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
        $oSQLiteDBConnection.open()


        $oSQLiteDBCommand = $oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext = "UPDATE CheckFirstRecords SET IsFirst = 0"


        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $oDBReader = $oSQLiteDBCommand.ExecuteNonQuery()

        $oSQLiteDBConnection.Close()
    }
    catch
    {
        Write-Log "Failed to Update IsFirst in database. Error: $($_.Exception.Message)" 3
    }

}

function ReadXMLAndInsertIfFirstTime
{
    param
    (
        [String]$subFolderName,
        [String]$filePath,
        [String]$Path
    )

    [XML]$xmlfile = Get-Content $filePath

    try
    {
        if (-not $Path.Contains("TachyonPipelineLibrary"))
        {
            $Path = $Path.ToString() + "\TachyonPipelineLibrary"
        }

        if ($xmlfile)
        {
            # ------------- Get Instructions Attributes --------------------------
            $myInstID = $xmlfile.InstructionDefinition.InstructionID
            $myInstName = $subFolderName + ' ' + $xmlfile.InstructionDefinition.Name
            $myInstReadablePayload = $xmlfile.InstructionDefinition.ReadablePayload
            $myInstDescription = $xmlfile.InstructionDefinition.Description
            $myInstType = $xmlfile.InstructionDefinition.InstructionType
            $myInstTtlMinutes = $xmlfile.InstructionDefinition.InstructionTtlMinutes
            $myInstResponseTtlMinutes = $xmlfile.InstructionDefinition.ResponseTtlMinutes
            $myInstVersion = $xmlfile.InstructionDefinition.Version
            $myInstAuthor = $xmlfile.InstructionDefinition.Author
            $myInstPayload = $xmlfile.InstructionDefinition.Payload.InnerXml
            $myInstComments = $xmlfile.InstructionDefinition.Comments
            $myInstSchemaJson = $xmlfile.InstructionDefinition.SchemaJson.InnerXml
            $myInstTaskGroups = $xmlfile.InstructionDefinition.TaskGroups.InnerXml
            $myInstAggregationJson = $xmlfile.InstructionDefinition.AggregationJson
            $mySignature = $xmlfile.InstructionDefinition.Signature.InnerXml

            if ($xmlfile.InstructionDefinition.Name -eq '' -or $xmlfile.InstructionDefinition.Name -eq $null)
            {
                $myInstName = $subFolderName + ' ' + $xmlfile.DocumentElement.Name
            }

            if ($xmlfile.InstructionDefinition.Description -eq '' -or $xmlfile.InstructionDefinition.Description -eq $null)
            {
                $myInstDescription = $subFolderName + ' ' + $xmlfile.DocumentElement.Description
            }

            if ($xmlfile.InstructionDefinition.InstructionType -eq '' -or $xmlfile.InstructionDefinition.InstructionType -eq $null)
            {
                $myInstType = $subFolderName + ' ' + $xmlfile.DocumentElement.Type
            }

            [Reflection.Assembly]::LoadFile($Path + "\System.Data.SQLite.dll")

            $sDatabasePath = $Path + "\TachyonInstructions.db"
            $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
            $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
            $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
            $oSQLiteDBConnection.open()

            InsertInstructionIntoSQL -InstName $myInstName -InstReadPayLoad $myInstReadablePayload -InstDesc $myInstDescription -InstType $myInstType -InstTtlMin $myInstTtlMinutes -InstTtlRespMin $myInstResponseTtlMinutes -InstVer $myInstVersion -InstAuth $myInstAuthor -InstPayload $myInstPayload -InstComments $myInstComments -InstSchemaJson $myInstSchemaJson -InstTaskGroups $myInstTaskGroups -InstAggrJson $myInstAggregationJson -InstSign $mySignature -PathOfSQLDll $Path -Connection $oSQLiteDBConnection

            $oSQLiteDBConnection.Close()
        }
    }
    catch
    {
        Write-Log "Failed to Insert Instructions. Error: $($_.Exception.Message)" 3
    }

}


function GetDataFromDB
{
    try
    {
        [Reflection.Assembly]::LoadFile(".\System.Data.SQLite.dll")

        $sDatabasePath=".\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString
        $oSQLiteDBConnection.open()

        $oSQLiteDBCommand=$oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext="select DISTINCT InstructionName from Instructions"
        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $oDBReader=$oSQLiteDBCommand.ExecuteReader()

        $oDBReader.GetValues()
        while($oDBReader.HasRows)
        {
            if($oDBReader.Read())
            {
                Write-Host $oDBReader["InstructionName"]
            }
        }
        $oDBReader.Close()
    }
    catch
    {
        Write-Log "Failed to Get Instructions. Error: $($_.Exception.Message)" 3
    }
}

function InsertInstructionIntoSQL
{
    param
    (
        [String]$InstName,           #1
        [String]$InstReadPayLoad,    #2
        [String]$InstDesc,           #3
        [String]$InstType,           #4
        [String]$InstTtlMin,         #5
        [String]$InstTtlRespMin,     #6
        [String]$InstVer,            #7
        [String]$InstAuth,           #8
        [String]$InstPayload,        #9
        [String]$InstComments,       #10
        [String]$InstSchemaJson,     #11
        [String]$InstTaskGroups,     #12
        [String]$InstAggrJson,       #13
        [String]$InstSign,           #14
        [String]$PathOfSQLDll,        #15
        [System.Data.SQLite.SQLiteConnection]$Connection         #16
    )



    try
    {
        if (-not $PathOfSQLDll.Contains("TachyonPipelineLibrary"))
        {
            $PathOfSQLDll = $PathOfSQLDll + "\TachyonPipelineLibrary"
        }

        [Reflection.Assembly]::LoadFile($PathOfSQLDll + "\System.Data.SQLite.dll")

        $sDatabasePath = $PathOfSQLDll + "\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString

        if ($Connection.State -ne 'Open')
        {
            $oSQLiteDBConnection.open()
        }
        else
        {
            $oSQLiteDBConnection = $Connection
        }

        #----------------- Begin INSERT Command --------------------------------------
        $oSQLiteDBCommand=$oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext="INSERT INTO Instructions (InstructionName, InstructionReadablePayload, InstructionDescription, InstructionType, InstructionTtlMinutes, InstructionResponseTtlMinutes, InstructionVersion,
                                        InstructionAuthor, InstructionPayload, InstructionComments, InstructionSchemaJson, InstructionTaskGroups, InstructionAggregationJson, InstructionSignature, InstructionCreatedDateTime) VALUES (@InstructionName,
                                        @InstructionReadablePayload, @InstructionDescription, @InstructionType, @InstructionTtlMinutes, @InstructionResponseTtlMinutes, @InstructionVersion,
                                        @InstructionAuthor, @InstructionPayload, @InstructionComments, @InstructionSchemaJson, @InstructionTaskGroups, @InstructionAggregationJson, @InstructionSignature, @InstructionCreatedDateTime)"

        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionName", $InstName);                              #1
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionReadablePayload", $InstReadPayLoad);            #2
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionDescription", $InstDesc);                       #3
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionType", $InstType);                              #4
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionTtlMinutes", $InstTtlMin);                      #5
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionResponseTtlMinutes", $InstTtlRespMin);          #6
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionVersion", $InstVer);                            #7
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionAuthor", $InstAuth);                            #8
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionPayload", $InstPayload);                        #9
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionComments", $InstComments);                      #10
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionSchemaJson", $InstSchemaJson);                  #11
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionTaskGroups", $InstTaskGroups);                  #12
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionAggregationJson", $InstAggrJson);               #13
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionSignature", $InstSign);                         #14
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionCreatedDateTime", $(Get-Date));                 #15


        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $oSQLiteDBCommand.ExecuteNonQuery()

        $oSQLiteDBConnection.Close();
        #------------------------  End of INSERT Command --------------------------------------
    }
    catch [Exception]
    {
        Write-Log "Failed to Insert Instructions for $InstName. Error: $($_.Exception.Message)" 3
    }
}

function Write-Log
{
    param ([String]$logString,
            [int]$logType = 1)

    try
    {
        $date = Get-Date

        $timeStr = "$($date.ToString(""HH"")):$($date.ToString(""mm"")):$($date.ToString(""ss"")).000+000"
        $dateStr = "$($date.ToString(""MM""))-$($date.ToString(""dd""))-$($date.ToString(""yyyy""))"
        $logOut = "<![LOG[$logString]LOG]!><time=""$timeStr"" date=""$dateStr"" component=""$($fileObj.BaseName)"" context="""" type=""$logType"" thread="""" file=""$($fileObj.BaseName)"">"

        $PathToScriptFile = Get-Location

        if (-not $PathToScriptFile.ToString().Contains("TachyonPipelineLibrary"))
        {
            $PathToScriptFile = $PathToScriptFile.ToString() + "\TachyonPipelineLibrary"
        }

        $script:sLogFile = $PathToScriptFile.ToString() + "\" + "TachyonInstructions" + $dateStr.ToString() + ".log"

        if($logType -eq 2)
        {
            Write-Warning $logString
        }
        elseif($logType -eq 3)
        {
            $host.ui.WriteErrorLine($logString)
        }
        else
        {
            write-host $logString
        }

        try
        {
            out-file -filePath $sLogFile -append -encoding "ASCII" -inputObject $logOut
        }
        catch
        {
            if($_.Exception.InnerException)
            {
                $errObj = $_.Exception.InnerException
            }
            else
            {
                $errObj = $_.Exception
            }
            $rc = [System.Runtime.InteropServices.Marshal]::GetHRForException($errObj)
            if($rc -eq 0x80070005)
            {
                # Access denied. Redirect log to the users temp folder!
                $script:sLogFile = (Join-Path $env:TEMP $global:logFileName)
            }
            out-file -filePath (Join-Path $env:TEMP $global:logFileName) -append -encoding "ASCII" -inputObject $logOut
        }
    }
    catch
    {
        Write-Host "Error occurred while creating a log file. Error: $($_.Exception.Message)"

    }

}


function UpdateInstructionsInSQL
{
    param
    (
        [String]$InstID,
        [String]$InstName,           #1
        [String]$InstReadPayLoad,    #2
        [String]$InstDesc,           #3
        [String]$InstType,           #4
        [String]$InstTtlMin,         #5
        [String]$InstTtlRespMin,     #6
        [String]$InstVer,            #7
        [String]$InstAuth,           #8
        [String]$InstPayload,        #9
        [String]$InstComments,       #10
        [String]$InstSchemaJson,     #11
        [String]$InstTaskGroups,     #12
        [String]$InstAggrJson,       #13
        [String]$InstSign,           #14
        [String]$PathOfSQLDll,       #15
        [System.Data.SQLite.SQLiteConnection]$Connection         #16
    )



    try
    {
        if (-not $PathOfSQLDll.Contains("TachyonPipelineLibrary"))
        {
            $PathOfSQLDll = $PathOfSQLDll + "\TachyonPipelineLibrary"
        }

        [Reflection.Assembly]::LoadFile($PathOfSQLDll + "\System.Data.SQLite.dll")

        #----------- Get the TOP Instruction ID --------------------------------------
        $sDatabasePath = $PathOfSQLDll + "\TachyonInstructions.db"
        $sDatabaseConnectionString=[string]::Format("data source={0}",$sDatabasePath)
        $oSQLiteDBConnection = New-Object System.Data.SQLite.SQLiteConnection
        $oSQLiteDBConnection.ConnectionString = $sDatabaseConnectionString

        if ($Connection.State -ne 'Open')
        {
            $oSQLiteDBConnection.open()
        }
        else
        {
            $oSQLiteDBConnection = $Connection
        }


        #----------------- Begin UPDATE Command --------------------------------------
        $oSQLiteDBCommand=$oSQLiteDBConnection.CreateCommand()
        $oSQLiteDBCommand.Commandtext="UPDATE   Instructions SET InstructionName = @InstructionName,
                                                InstructionReadablePayload = @InstructionReadablePayload,
                                                InstructionDescription = @InstructionDescription,
                                                InstructionType = @InstructionType,
                                                InstructionTtlMinutes = @InstructionTtlMinutes,
                                                InstructionResponseTtlMinutes = @InstructionResponseTtlMinutes,
                                                InstructionVersion = @InstructionVersion,
                                                InstructionAuthor = @InstructionAuthor,
                                                InstructionPayload = @InstructionPayload,
                                                InstructionComments = @InstructionComments,
                                                InstructionSchemaJson = @InstructionSchemaJson,
                                                InstructionTaskGroups = @InstructionTaskGroups,
                                                InstructionAggregationJson = @InstructionAggregationJson,
                                                InstructionSignature = @InstructionSignature,
                                                InstructionModifiedDateTime = @InstructionModifiedDateTime
                                                WHERE InstructionID = @InstructionID"

        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionName", $InstName);                              #1
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionReadablePayload", $InstReadPayLoad);            #2
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionDescription", $InstDesc);                       #3
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionType", $InstType);                              #4
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionTtlMinutes", $InstTtlMin);                      #5
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionResponseTtlMinutes", $InstTtlRespMin);          #6
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionVersion", $InstVer);                            #7
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionAuthor", $InstAuth);                            #8
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionPayload", $InstPayload);                        #9
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionComments", $InstComments);                      #10
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionSchemaJson", $InstSchemaJson);                  #11
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionTaskGroups", $InstTaskGroups);                  #12
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionAggregationJson", $InstAggrJson);               #13
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionSignature", $InstSign);                         #14
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionModifiedDateTime", $(Get-Date));                #15
        $oSQLiteDBCommand.Parameters.AddWithValue("InstructionID", $InstID);                                  #16


        $oSQLiteDBCommand.CommandType = [System.Data.CommandType]::Text
        $oSQLiteDBCommand.ExecuteNonQuery()

        $oSQLiteDBConnection.Close();
        #------------------------  End of INSERT Command --------------------------------------
    }
    catch [Exception]
    {
        Write-Log "Failed to Update Instructions for $InstName. Error: $($_.Exception.Message)" 3
    }
}


#Set execution policy to bypass
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$Global:CurrentLocation = Get-Location

Write-Log "Script is triggered by the pipeline at $(Get-Date)" 1
Write-Log "===================================================" 1

Write-Log "Current location of the script is - $CurrentLocation" 1
Write-Log "===================================================" 1


#Read all the folders for updated content
ReadAllFolders($CurrentLocation)



#>

