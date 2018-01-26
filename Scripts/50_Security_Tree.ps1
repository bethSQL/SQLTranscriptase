<#
.SYNOPSIS
    Gets all Server and Database Permissions for all Logins
	
.DESCRIPTION
      
.EXAMPLE
    50_Security_Tree.ps1 localhost
	
.EXAMPLE
    50_Security_Tree.ps1 server01 sa password

.Inputs
    ServerName\instance, [SQLUser], [SQLPassword]

.Outputs

	
.NOTES


.LINK
	https://github.com/gwalkey
	
	
#>


Param(
  [string]$SQLInstance="localhost",
  [string]$myuser,
  [string]$mypass
)


# ----------------
# - Initializing 
# ----------------
Set-StrictMode -Version latest;

[string]$BaseFolder = (Get-Item -Path ".\" -Verbose).FullName

# Splash
Write-Host  -f Yellow -b Black "50 - Security Tree"
Write-Output "Server $SQLInstance"

# Functions
function ConnectWinAuth
{   
    [CmdletBinding()]
    Param([String]$SQLExec,
          [String]$SQLInstance,
          [String]$Database)

    Process
    {
		# Open connection and Execute sql against server using Windows Auth
		$DataSet = New-Object System.Data.DataSet
		$SQLConnectionString = "Data Source=$SQLInstance;Initial Catalog=$Database;Integrated Security=SSPI;" 
		$Connection = New-Object System.Data.SqlClient.SqlConnection
		$Connection.ConnectionString = $SQLConnectionString
		$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd.CommandText = $SQLExec
		$SqlCmd.Connection = $Connection
		$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$SqlAdapter.SelectCommand = $SqlCmd
    
		# Insert results into Dataset table
		$SqlAdapter.Fill($DataSet) |out-null
        if ($DataSet.Tables.Count -ne 0) 
        {
            $sqlresults = $DataSet.Tables[0]
        }
        else
        {
            $sqlresults =$null
        }

		# Close connection to sql server
		$Connection.Close()		    

        Write-Output $sqlresults
    }
}

function ConnectSQLAuth
{   
[CmdletBinding()]
    Param([String]$SQLExec,
          [String]$SQLInstance,
          [String]$Database,
          [String]$User,
          [String]$Password)

    Process
    {
		# Open connection and Execute sql against server using Windows Auth
		$DataSet = New-Object System.Data.DataSet
		$SQLConnectionString = "Data Source=$SQLInstance;Initial Catalog=$Database;User ID=$User;Password=$Password" 
		$Connection = New-Object System.Data.SqlClient.SqlConnection
		$Connection.ConnectionString = $SQLConnectionString
		$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
		$SqlCmd.CommandText = $SQLExec
		$SqlCmd.Connection = $Connection
		$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$SqlAdapter.SelectCommand = $SqlCmd
    
		# Insert results into Dataset table
		$SqlAdapter.Fill($DataSet) |out-null
        if ($DataSet.Tables.Count -ne 0) 
        {
            $sqlresults = $DataSet.Tables[0]
        }
        else
        {
            $sqlresults =$null
        }

		# Close connection to sql server
		$Connection.Close()		    

        Write-Output $sqlresults
    }
}

# --------
# Startup
# --------
# Server connection check
try
{
    if ($mypass.Length -ge 1 -and $myuser.Length -ge 1) 
    {
        $results = ConnectSQLAuth "select serverproperty('productversion')" -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass        
        $serverauth="sql"
    }
    else
    {
        $results = ConnectWinAuth "select serverproperty('productversion')" -SQLInstance $SQLInstance -Database "master"
        $serverauth = "win"
    }

    if($results -ne $null)
    {
        Write-Output ("SQL Version: {0}" -f $results.Column1)
    }

}
catch
{
    Write-Output ("Error: {0}" -f $Error[0])
    Write-Host -f red "$SQLInstance appears offline - Try Windows Authorization."
    Set-Location $BaseFolder
	exit
}



# Create base output folder
$output_path = "$BaseFolder\$SQLInstance\50 - Security Tree\"
if(!(test-path -path $output_path))
{
    mkdir $output_path | Out-Null
}


# ---------------------------
# Get Public FSR Permissions
# ---------------------------
$myPFSRfile = $output_path+"Public_Fixed_Server_Role.txt"
"`r`nPublic Fixed Server Role permissions:" | out-file $myPFSRfile -Append

$sql5=
"
SELECT 
    sp.state_desc, 
    sp.permission_name, 
    sp.class_desc, 
    sp.major_id, 
    sp.minor_id, 
    e.[name] as [endpointname],
    l.[name]
FROM sys.server_permissions AS sp
JOIN sys.server_principals AS l
    ON sp.grantee_principal_id = l.principal_id
LEFT JOIN sys.endpoints AS e
    ON sp.major_id = e.endpoint_id
WHERE l.name = 'public';
"

if ($serverauth -eq "win")
{
    $PublicPerms = ConnectWinAuth -SQLExec $sql5 -SQLInstance $SQLInstance -Database "master"
}
else
{
    $PublicPerms = ConnectSQLAuth -SQLExec $sql5 -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass
}
    
$statement =''
foreach ($perm in $PublicPerms)
{
    if ($perm.class_desc -eq 'ENDPOINT')
    {
        $statement = '     '+$Perm.state_desc +' '+$Perm.Permission_name+' on '+$Perm.Class_desc+"::"+$perm.endpointname+' to '+$perm.name
    }
    else
    {
        $statement = '     '+$Perm.state_desc +' '+$Perm.Permission_name+' to '+$Perm.Name
    }
    $statement | out-file $myPFSRfile -Append

}

# Get all online databases
$sql1 = 
"
SELECT
	*
FROM
	sys.databases
WHERE 
    [state]=0 and [name]<>'tempdb'
order by 
    [name]
"

if ($serverauth -eq "win")
{
    $Databases = ConnectWinAuth $sql1 -SQLInstance $SQLInstance -Database "master"
}
else
{
    $Databases = ConnectSQLAuth $sql1 -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass
}

# Get Logins to Process
$sql2=
"
SELECT 
	[NAME],
	[type],
	[default_database_name],
	[is_disabled]
FROM 
	sys.server_principals
WHERE 
	[name] NOT LIKE 'NT Service%' AND 
	[name] NOT LIKE ('NT AUTHORITY%') AND
	LEFT([NAME],2)<>'##' AND
    [name] NOT IN ('BUILTIN\Administrators','distributor_admin') AND
	[TYPE] <>'R'
ORDER BY 
	1
"

if ($serverauth -eq "win")
{
    $logins = ConnectWinAuth -SQLExec $sql2 -SQLInstance $SQLInstance -Database "master"
}
else
{
    $logins = ConnectSQLAuth -SQLExec $sql2 -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass
}


foreach($myLogin in $logins)
{
    # Create Output File
    $myLoginName = $fixedDBName = $myLogin.name.replace('\','_')
    $myoutputfile = $output_path+$myLoginName+".txt"
    Write-Output("SQL Server Permissions for [{0}]" -f $myLogin.name) 
    Write-Output("SQL Server Permissions for [{0}]" -f $myLogin.name) | out-file $myoutputfile -Append    
    Write-Output("Default Database: {0}" -f $myLogin.default_database_name) | out-file $myoutputfile -Append
    if ($myLogin.is_disabled -eq '1')
    {
        Write-Output("Login is disabled") | out-file $myoutputfile -Append
    }
    

    $login = $myLogin.name


    # --------------------------------------
    # Get Explicit Server-Level Permissions
    # --------------------------------------
    "`r`nServer-Level Permissions:" | out-file $myoutputfile -Append

    $sql3 = 
    "
    SELECT 
    	x.[name],
    	x.[type_desc],	
    	x.[type],
    	p.[state_desc] AS 'Action',
    	p.[permission_name] AS 'Perm',
    	p.[class_desc] AS 'On'
    FROM 
    	sys.server_permissions p
    JOIN 
    	sys.server_principals x
    ON 
    	p.grantee_principal_id=x.principal_id
    WHERE 
        x.[name] = '$Login'
    "

    if ($serverauth -eq "win")
    {
        $ServerPerms = ConnectWinAuth -SQLExec $sql3 -SQLInstance $SQLInstance -Database "master"
    }
    else
    {
        $ServerPerms = ConnectSQLAuth -SQLExec $sql3 -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass
    }

    foreach ($perm in $ServerPerms)
    {
        $statement = '     '+$Perm.action +' '+$Perm.Perm+' to '+$Perm.Name
        $statement | out-file $myoutputfile -Append

    }
    

    # ---------------------------------
    # Get Fixed Server Role Permissions
    # ---------------------------------
    "`r`nFixed Server Role Permissions:" | out-file $myoutputfile -Append

    $sql4=
    "
    SELECT 	
	    sRole.name AS [Server_Role_Name]
    FROM sys.server_role_members AS sRo  
    JOIN sys.server_principals AS sPrinc  
        ON sRo.member_principal_id = sPrinc.principal_id  
    JOIN sys.server_principals AS sRole  
        ON sRo.role_principal_id = sRole.principal_id
    WHERE 
    	sprinc.name='$login'
    "
    
    if ($serverauth -eq "win")
    {
        $FSRPerms = ConnectWinAuth -SQLExec $sql4 -SQLInstance $SQLInstance -Database "master"
    }
    else
    {
        $FSRPerms = ConnectSQLAuth -SQLExec $sql4 -SQLInstance $SQLInstance -Database "master" -User $myuser -Password $mypass
    }

    $statement=''
    foreach($FSR in $FSRPerms)
    {
        switch ($FSR.Server_Role_Name)
        {            
            'securityadmin' {$statement+= '     '+$login+" is a member of the [Securityadmin] Fixed Server Role`r`n"}
            'serveradmin'   {$statement+= '     '+$login+" is a member of the [Serveradmin] Fixed Server Role`r`n"}
            'setupadmin'    {$statement+= '     '+$login+" is a member of the [Setupadmin] Fixed Server Role`r`n"}
            'processadmin'  {$statement+= '     '+$login+" is a member of the [Processadmin] Fixed Server Role`r`n"}
            'diskadmin'     {$statement+= '     '+$login+" is a member of the [Diskadmin] Fixed Server Role`r`n"}
            'dbcreator'     {$statement+= '     '+$login+" is a member of the [DBcreator] Fixed Server Role`r`n"}
            'bulkadmin'     {$statement+= '     '+$login+" is a member of the [Bulkadmin] Fixed Server Role`r`n"}
            'sysadmin'      {$statement+= '     '+$login+" is a member of the [Sysadmin] Fixed Server Role`r`n"}
        }
    }

    $statement | out-file $myoutputfile -Append
    


    

    # ----------------------------------
    # Get Permissions for Each Database
    # ----------------------------------

    Write-Output("`r`nDatabase Permissions:") | out-file $myoutputfile -Append
    foreach($database in $Databases)
    {
        $DBName = $database.name

        # Get the Login-to-User mapping first
        $sqll2u=
        "
        SELECT 
	        susers.[name] AS [ServerLogin],
	        users.[name] AS [DBUser]
        from 
	        sys.server_principals susers
        JOIN
	        sys.database_principals users 
        on 
	        susers.sid = users.sid
        where
            susers.[name] = '$Login'
        "

        if ($serverauth -eq "win")
        {
            $LoginToUserMap = ConnectWinAuth -SQLExec $sqll2u -SQLInstance $SQLInstance -Database $DBName
        }
        else
        {
            $LoginToUserMap = ConnectSQLAuth -SQLExec $sqll2u -SQLInstance $SQLInstance -Database $DBName -User $myuser -Password $mypass
        }

        # Skip the Database if there is no Login to User Mapping
        if ($LoginToUserMap -eq $null) {continue}

        $DBUser = $LoginToUserMap.DBUser

        Write-Output("[{0}]" -f $DBName) | out-file $myoutputfile -Append
        Write-Output("    Login-to-User mapping:[{1}]-->[{2}]" -f $DBName, $LoginToUserMap.ServerLogin, $LoginToUserMap.DBUser) | out-file $myoutputfile -Append


        # Get database-scoped permissions at database level
        #"Database-scoped permissions at the database level:" | out-file $myoutputfile -Append

        $sql6=
        "
        SELECT
            perms.class_desc as [PermissionClass],
            perms.permission_name AS Permission,
            type_desc AS [PrincipalType],
            prin.name as Principal
        FROM 
            sys.database_permissions perms
        JOIN
            sys.database_principals prin
        ON
            perms.grantee_principal_id = prin.principal_id
        WHERE 
            grantee_principal_id NOT IN (DATABASE_PRINCIPAL_ID('guest'), DATABASE_PRINCIPAL_ID('public')) 
            AND perms.class = 0
            AND prin.name = '$DBUser'
        "
        if ($serverauth -eq "win")
        {
            $DBScopedPerms = ConnectWinAuth -SQLExec $sql6 -SQLInstance $SQLInstance -Database $DBName
        }
        else
        {
            $DBScopedPerms = ConnectSQLAuth -SQLExec $sql6 -SQLInstance $SQLInstance -Database $DBName -User $myuser -Password $mypass
        }
        
        # Script out
        $statement =''
        foreach ($perm in $DBScopedPerms)
        {
            $statement = '     GRANT '+$Perm.Permission+' to ['+$perm.principal+']'
            $statement | out-file $myoutputfile -Append

        }
        


        # Get high impact database-scoped permissions at object level
        #"Database-scoped permissions at the object level:" | out-file $myoutputfile -Append
        $sql7=
        "
        SELECT 
	        perms.class_desc as [PermissionClass], 
	        OBJECT_SCHEMA_NAME(major_id) as [Schema], 
	        OBJECT_NAME(major_id) as [Object], 
	        perms.permission_name AS Permission, 
	        type_desc AS [PrincipalType], 
	        prin.name as Principal
        FROM
	        sys.database_permissions perms
        JOIN
	        sys.database_principals prin
        ON
	        perms.grantee_principal_id = prin.principal_id 
        WHERE 
	        grantee_principal_id NOT IN (DATABASE_PRINCIPAL_ID('guest'), DATABASE_PRINCIPAL_ID('public')) 
            AND perms.class = 1
            AND prin.name = '$DBUser'
        "

        if ($serverauth -eq "win")
        {
            $DBObjectPerms = ConnectWinAuth -SQLExec $sql7 -SQLInstance $SQLInstance -Database $DBName
        }
        else
        {
            $DBObjectPerms = ConnectSQLAuth -SQLExec $sql7 -SQLInstance $SQLInstance -Database $DBName -User $myuser -Password $mypass
        }

        $statement =''
        foreach ($perm in $DBObjectPerms)
        {
            $statement = '     GRANT '+$Perm.Permission+' on ['+$perm.schema+']['+$perm.Object+'] to ['+$perm.principal+']'
            $statement | out-file $myoutputfile -Append

        }
        
        # Get Database Role Membership
        #"`r`nFixed Database Role Memberships:" | out-file $myoutputfile -Append
        $sql8=
        "
        SELECT 
	        dRole.name AS [DBRole]	
        FROM 
            sys.database_role_members AS dRo  
        JOIN 
            sys.database_principals AS dPrinc  
        ON 
            dRo.member_principal_id = dPrinc.principal_id  
        JOIN 
            sys.database_principals AS dRole  
        ON 
            dRo.role_principal_id = dRole.principal_id  
        WHERE
    	    dPrinc.name='$DBUser'
        "
    
        if ($serverauth -eq "win")
        {
            $DBRoleMemberships = ConnectWinAuth -SQLExec $sql8 -SQLInstance $SQLInstance -Database $DBName
        }
        else
        {
            $DBRoleMemberships = ConnectSQLAuth -SQLExec $sql8 -SQLInstance $SQLInstance -Database $DBName -User $myuser -Password $mypass
        }

        $statement=''
        foreach($DBRole in $DBRoleMemberships)
        {
            $myRole = $DBRole.DBRole
            switch ($myRole)
            {            
                'db_owner'           {
                                        '     ['+$DBUser+"] is a member of the [db_owner] Fixed Database Role" | out-file $myoutputfile -Append
                                     }

                'db_securityadmin'   {
                                        '     ['+$DBUser+"] is a member of the [db_securityadmin] Fixed Database Role" | out-file $myoutputfile -Append
                                     }

                'db_accessadmin'     {
                                        '     ['+$DBUser+"] is a member of the [db_accessadmin] Fixed Database Role" | out-file $myoutputfile -Append
                                     }

                'db_backupoperator'  {
                                        '     ['+$DBUser+"] is a member of the [db_backupoperator] Fixed Database Role" | out-file $myoutputfile -Append
                                     }

                'db_ddladmin'        {
                                        '     ['+$DBUser+"] is a member of the [db_ddladmin] Fixed Database Role" | out-file $myoutputfile -Append
                                        '          GRANT ALTER ANY ASSEMBLY'+$DBName+' to ['+$DBUser+']' | out-file $myoutputfile -Append
                                        
                                     }

                'db_datawriter'      {                                        
                                        '     ['+$DBUser+"] is a member of the [db_datawriter] Fixed Database Role" | out-file $myoutputfile -Append
                                        '          GRANT INSERT on DATABASE::'+$DBName+' to ['+$DBUser+']' | out-file $myoutputfile -Append
                                        '          GRANT DELETE on DATABASE::'+$DBName+' to ['+$DBUser+']' | out-file $myoutputfile -Append
                                        '          GRANT UPDATE on DATABASE::'+$DBName+' to ['+$DBUser+']' | out-file $myoutputfile -Append                                        
                                     }

                'db_datareader'      {                                        
                                        '     ['+$DBUser+"] is a member of the [db_datareader] Fixed Database Role" | out-file $myoutputfile -Append
                                        '          GRANT SELECT on DATABASE::'+$DBName+' to '+$DBUser  | out-file $myoutputfile -Append                                        
                                     }

                'db_denydatawriter'  {
                                        '     ['+$DBUser+"] is a member of the [db_denydatawriter] Fixed Database Role" | out-file $myoutputfile -Append                                        
                                     }

                'db_denydatareader'  {
                                        '     ['+$DBUser+"] is a member of the [db_denydatareader] Fixed Database Role" | out-file $myoutputfile -Append                                        
                                     }

                default              {
                                        '     ['+$DBUser+"] is a member of the [$myRole] Fixed Database Role" | out-file $myoutputfile -Append                                        
                                     }
            }
        }

        
        

    } # Next Database
} # Next Login





# Return To Base
set-location $BaseFolder

