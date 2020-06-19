$serverHostingADConnect = "servername"

$msgBoxAnswer = [System.Windows.MessageBox]::Show('Run Delta Azure AD Sync?','Start-ADSyncSyncCycle','YesNoCancel','Question')
	switch ($msgBoxAnswer){
	'Yes' {
		$ADSync = Invoke-Command -Computername $serverHostingADConnect -scriptblock { start-adsyncsynccycle -PolicyType Delta}
		[System.Windows.MessageBox]::Show('$ADSync.result','Start-ADSyncSyncCycle','OK')
	}
	'No' {
		$msgBoxSecondAnswer = [System.Windows.MessageBox]::Show('Run Initial/Full Azure AD Sync?','Start-ADSyncSyncCycle','OKCancel','Question')
            switch ($msgBoxSecondAnswer){
			'Yes' {
				$ADSync = Invoke-Command -Computername $serverHostingADConnect -scriptblock { start-adsyncsynccycle -PolicyType Initial}
				[System.Windows.MessageBox]::Show('$ADSync.result','Start-ADSyncSyncCycle','OK')
	            }
            }
         }
}
