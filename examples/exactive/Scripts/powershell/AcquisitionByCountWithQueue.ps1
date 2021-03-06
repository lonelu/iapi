<#
 # Copyright(c) 2011 - 2018 Thermo Fisher Scientific - LSMS
 # 
 # Permission is hereby granted, free of charge, to any person obtaining a copy
 # of this software and associated documentation files (the "Software"), to deal
 # in the Software without restriction, including without limitation the rights
 # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 # copies of the Software, and to permit persons to whom the Software is
 # furnished to do so, subject to the following conditions:
 # 
 # The above copyright notice and this permission notice shall be included in all
 # copies or substantial portions of the Software.
 # 
 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 # SOFTWARE.
 #>

<#
Sample script to demonstrate how to run an acquisition limited by count and get all MsScan data.

When subscribing to the event handler MsScanArrived of MsScanContainer with Register-ObjectEvent,
you should keep in mind, that the registered action is called in another thread. If another MsScan
is arrived before the event is handled the MsScan object is disposed. To prevent the MsScan data 
from getting disposed you must get a reference to the 
MsScan data by calling GetScan on the MsScanEventArgs. Note the reference to Ms scan data must be
released by calling the Dispose methode.

This example shows how to use the helper class MsScanQueue from ScanQueue.dll to access the Ms scans
from container of Ms scan information stored in the MsScanQueue. The class MsScanQueue raise the event  
MsScanQueued, if a Ms scan is put in the queue, in the PowerShell event handler function $MsScanQueued
the Ms scan data will be dequeued and processed.  
#>

# path to ScanQueue.dll, usually in the instrument bin folder
$pathScanQueue = "C:\Xcalibur\system\Exactive\bin\ScanQueue.dll" 

# event handler is invoked when the connection state of the instrument has changed
$ConnectionChanged =
{
    #prints the connection state
    if ($Event.Sender.Connected -eq $True)
    {
        Write-Host $Event.Sender.InstrumentName " connected" -fore green        
    }
    else
    {
        Write-Host $Event.Sender.InstrumentName " not connected" -fore red 
    }      
}

# event handler is invoked when a Ms scan has queued
$MsScanQueued = 
{
    $global:scanCount = $global:scanCount + 1
    try
    {   
        # Gets one scan from the event arguments
        $scan = $Event.Sender.Dequeue()
        # prints the centriod count
        if ($scan.HasCentroidInformation)
        {
            $maxInt = 0;
            $maxIntMz = 0;
            foreach ($centroid in $scan.Centroids)
            {
                if ($maxInt -lt $centroid.Intensity)
                {
                    $maxInt = $centroid.Intensity
                    $maxIntMz = $centroid.Mz
                }
            }
            Write-Host $global:scanCount`t $scan.CentroidCount`t$maxIntMz`t$maxInt`t $Event.Sender.Count
        }
        else
        {
            Write-Host $global:scanCount "No centroid information"
        }
    	    # releases the MsScan data
        $scan.Dispose()
    }
    catch
    {
        Write-Host "Failed to access scan" $global:scanCount -fore red
    }
}

# removes all events and event subscribers
Function Remove-EventAndSubscriber
{
    Get-EventSubscriber | Unregister-Event
    Get-Event | Remove-Event
}

try
{
    # instantiate instrument API for the first instrument
    $instrumentAccessContainer = New-Object -ComObject "Thermo Exactive.API_Clr2_32_V1"
    # get the first instrument
    $instrumentAccess = $instrumentAccessContainer.Get(1)
    # get the MsScanContainer
    $msScancontainer = $instrumentAccess.GetMsScanContainer(0)
       
    $null = [System.Reflection.Assembly]::LoadFrom($pathScanQueue);
    $msScanQueue = New-Object Thermo.Exactive.ApiExamples.ScanQueue.MsScanQueue(,$msScancontainer)
        
    # print the instrument name and id
    $instrumentAccess.InstrumentName + $instrumentAccess.InstrumentId

    $AcquisitionContinuation = [Thermo.Interfaces.ExactiveAccess_V1.Control.Acquisition.Workflow.AcquisitionContinuation]
    $AcquisitionSystemNode = [Thermo.Interfaces.InstrumentAccess_V1.Control.Acquisition.SystemMode]

    # get notified when the instrument connection has been changed
    $null = Register-ObjectEvent $instrumentAccess ConnectionChanged -SourceIdentifier Instrument.ConnectionChanged -Action $ConnectionChanged

    # create a 200 scan acquisition with setting the instrument to standby afterwards
    $acq = $instrumentAccess.Control.Acquisition.CreateAcquisitionLimitedByCount(200)
    $acq.Continuation = $AcquisitionContinuation::Standby

    # get notified when the instrument state has been changed
    $null = Register-ObjectEvent $instrumentAccess.Control.Acquisition StateChanged -SourceIdentifier Instrument.StateChanged

    #check if instrument is on
    if ($acq.SystemMode -ne  $AcquisitionSystemNode::On)
    {
        # switch the instrument on and wait until state has been changed
        $null = $instrumentAccess.Control.Acquisition.SetMode($instrumentAccess.Control.Acquisition.CreateOnMode());
        $null = Wait-Event -SourceIdentifier Instrument.StateChanged
    }

    # get notified when a MsScan is queued in MsScanBridge ($global:bridge)
    $null = Register-ObjectEvent $msScanQueue MsScanQueued -SourceIdentifier Instrument.MsScanQueued -Action $MsScanQueued

    #start the acquistion
    $global:scanCount = 0
    $null = $instrumentAccess.Control.Acquisition.StartAcquisition($acq)

    #just keep the script running, stop with ctrl+c
    Wait-Event -SourceIdentifier Dummy
}
finally
{
    # because the script might stop with ctrl+c the event subscribers maystill active
    # so remove all events and event subscribers
    Remove-EventAndSubscriber

    if ($msScanQueue -ne $null)
    {
        $msScanQueue.Dispose();
        $msScanQueue = $null;
    }
}