USE [r2w_db]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [Company].[sp_AssignWildcardContentAccess] AS

BEGIN

SET NOCOUNT ON;
DECLARE
      @TotalTime        INT
    , @StartTime        DATETIME2(7)
    , @FolderTime       DATETIME2(7)
    , @MemberTime       DATETIME2(7)
    , @InsertRecordTime DATETIME2(7)
    , @Level4Time       DATETIME2(7)
    , @Level3Time       DATETIME2(7)
    , @Level2Time       DATETIME2(7)
    , @Level1Time       DATETIME2(7)
    , @EndTime          DATETIME2(7)
    , @TimeFormatted    TIME(7)
    , @RowCount         INT

-- Start taking timestamps to monitor performance
SET @StartTime = SYSDATETIME();
PRINT 'START Date/Time:                          ['
    + CAST(@StartTime AS VARCHAR) + ']';
PRINT ' ';

-- Create temporary table #Output, which is used for logging
If (OBJECT_ID('tempdb..#Output') Is Not Null)
    Drop Table #Output;
CREATE TABLE #Output (
      OutputTableId  INT Identity(1,1) NOT NULL PRIMARY KEY
    , FolderAccessId INT
    , MemberId       INT
    , FolderId       INT
)

-- Create in populate temporary table #Folder from dbo.folder
If (OBJECT_ID('tempdb..#Folder') Is Not Null)
    Drop Table #Folder;
CREATE TABLE #Folder (
	  path  varchar(200)    PRIMARY KEY
	, id    INT             NOT NULL
	, ParentId		 INT	NOT NULL
);

INSERT INTO #Folder (path, id, parentid)
SELECT path, id, parentid
FROM r2w_db.dbo.folder (NOLOCK)
ORDER BY path
OPTION (MAXDOP 2);

SET @FolderTime = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @StartTime, @FolderTime);
PRINT 'FOLDER Table Populated, Date/Time:        ['
    + CAST(@FolderTime AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Create in populate temporary table #Member from dbo.member
If (OBJECT_ID('tempdb..#Member') Is Not Null)
    Drop Table #Member;
CREATE TABLE #Member (
      name      VARCHAR (200)   NOT NULL
	, id        INT             NOT NULL
	, domain    varchar (20)    NOT NULL
	, PRIMARY KEY (name, domain)
);

INSERT INTO #Member (name, id, domain)
SELECT name, id, domain
FROM r2w_db.dbo.member m (NOLOCK)
OPTION (MAXDOP 2);

SET @MemberTime = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @FolderTime, @MemberTime);
PRINT 'MEMBER Table Populated, Date/Time:        ['
    + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Create in populate temporary #InsertRecords from Company.ContentAccessControl
If (OBJECT_ID('tempdb..#InsertRecords') Is Not Null)
    Drop Table #InsertRecords;
CREATE TABLE #InsertRecords (
      MemberId		    INT             NOT NULL
    , FolderId		    INT             NOT NULL
    , MemberName		VARCHAR (200)   NOT NULL
    , FolderPath		varchar (200)   NOT NULL
    , PRIMARY KEY (MemberId, FolderId)
);

INSERT INTO #InsertRecords (
      MemberId
    , folderid
    , MemberName
    , FolderPath
)
SELECT MemberId     = m.id
	 , FolderId     = f.id
     , MemberName   = m.name
     , FolderPath   = f.[path]
FROM r2w_db.Company.ContentAccessControl cac (NOLOCK)
JOIN #Member m (NOLOCK)
	ON m.name LIKE cac.MemberExpression
JOIN #Folder f (NOLOCK)
	ON f.path LIKE cac.FolderPathExpression
OPTION (MAXDOP 2);

SET @InsertRecordTime = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @MemberTime, @InsertRecordTime);
PRINT 'INSERTRECORDS Table Populated, Date/Time: ['
    + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';
PRINT ' ';

-- Insert new entries into FolderAccess
-- Level 4
TRUNCATE TABLE #Output;

INSERT INTO r2w_db.dbo.folderaccess (
      folderid
    , memberid
    , folderpermission
    , delegationpermission
    , syncpermission
    , propagative
)
OUTPUT
      INSERTED.id
    , INSERTED.memberid
    , INSERTED.folderid
    INTO #Output
SELECT
      folderid             = ir.FolderId
    , memberid             = ir.MemberId
    , folderpermission     = 'R'
    , delegationpermission = 'N'
    , syncpermission       = 'N'
    , propagative          = 0
FROM #InsertRecords ir (NOLOCK)
WHERE NOT EXISTS (
    SELECT 1
    FROM r2w_db.dbo.folderaccess fa (NOLOCK)
    WHERE   fa.folderid = ir.FolderId
        AND fa.memberid = ir.MemberId
)
OPTION (MAXDOP 2);

-- Log new folderaccess entries into ContentAccessControlLog
SET @RowCount = @@ROWCOUNT;

INSERT INTO r2w_db.Company.ContentAccessControlLog (
      Date_Time
	, FolderAccessId
    , InsertEntryLevel
	, MemberId
	, FolderId
	, MemberName
	, FolderPath
)
SELECT
      Date_Time         = SYSDATETIME()
	, FolderAccessId    = o.FolderAccessId
    , InsertEntryLevel  = 4
	, MemberId          = o.MemberId
	, FolderId          = o.FolderId
	, MemberName        = ir.MemberName
	, FolderPath        = ir.FolderPath
FROM #Output o (NOLOCK)
JOIN #InsertRecords ir (NOLOCK)
    ON ir.MemberId = o.MemberId
    AND ir.FolderId = o.FolderId
OPTION (MAXDOP 2);

SET @Level4Time = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @InsertRecordTime, @Level4Time);
PRINT 'Number of LEVEL 4 rows inserted: ' + CAST(@RowCount as VARCHAR)
    + ', Date/Time: [' + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Insert new entries into FolderAccess
-- Level 3
TRUNCATE TABLE #Output;

INSERT INTO r2w_db.dbo.FolderAccess (
      folderid
    , memberid
    , folderpermission
    , delegationpermission
    , syncpermission
    , propagative
)
OUTPUT
      INSERTED.id
    , INSERTED.memberid
    , INSERTED.folderid
    INTO #Output
SELECT DISTINCT
      folderid             = fp.id
    , memberid             = ir.MemberId
    , folderpermission     = 'R'
    , delegationpermission = 'N'
    , syncpermission       = 'N'
    , propagative          = 0
FROM #InsertRecords ir (NOLOCK)
JOIN #folder f (NOLOCK)
    ON f.id = ir.FolderId
JOIN #folder fp (NOLOCK)
    ON f.parentid = fp.id
WHERE NOT EXISTS 
	(SELECT 1
    FROM r2w_db.dbo.folderaccess fa (NOLOCK)
    WHERE fa.folderid = fp.id
    AND fa.memberid = ir.MemberId)
AND fp.parentid <> 1
OPTION (MAXDOP 2);

-- Log new folderaccess entries into ContentAccessControlLog
SET @RowCount = @@ROWCOUNT;

INSERT INTO r2w_db.Company.ContentAccessControlLog (
      Date_Time
	, FolderAccessId
    , InsertEntryLevel
	, MemberId
	, FolderId
	, MemberName
	, FolderPath
)
SELECT Date_Time         = SYSDATETIME()
	, FolderAccessId    = o.FolderAccessId
    , InsertEntryLevel  = 3
	, MemberId          = o.MemberId
	, FolderId          = o.FolderId
	, MemberName        = m.name
	, FolderPath        = f.path
FROM #Output o (NOLOCK)
JOIN #member m (NOLOCK)
    ON o.MemberId = m.id
JOIN #Folder f (NOLOCK)
    ON o.FolderId = f.id
OPTION (MAXDOP 2);

SET @Level3Time = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @Level4Time, @Level3Time);
PRINT 'Number of LEVEL 3 rows inserted: ' + CAST(@RowCount as VARCHAR)
    + ', Date/Time: [' + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Insert new entries into FolderAccess
-- Level 2
TRUNCATE TABLE #Output;

INSERT INTO r2w_db.dbo.FolderAccess (
      folderid
    , memberid
    , folderpermission
    , delegationpermission
    , syncpermission
    , propagative
)
OUTPUT
      INSERTED.id
    , INSERTED.memberid
    , INSERTED.folderid
    INTO #Output
SELECT DISTINCT
      folderid             = fpp.id
    , memberid             = ir.MemberId
    , folderpermission     = 'R'
    , delegationpermission = 'N'
    , syncpermission       = 'N'
    , propagative          = 0
FROM #InsertRecords ir (NOLOCK)
JOIN r2w_db.dbo.folder f (NOLOCK)
    ON f.id = ir.FolderId
JOIN r2w_db.dbo.folder fp (NOLOCK)
    ON f.parentid = fp.id
JOIN r2w_db.dbo.folder fpp (NOLOCK)
	ON fp.parentid = fpp.id
WHERE NOT EXISTS 
	(SELECT 1
    FROM r2w_db.dbo.folderaccess fa (NOLOCK)
    WHERE   fa.folderid = fpp.id
        AND fa.memberid = ir.MemberId)
AND fpp.parentid != 1
OPTION (MAXDOP 2);

-- Log new folderaccess entries into ContentAccessControlLog
SET @RowCount = @@ROWCOUNT;

INSERT INTO r2w_db.Company.ContentAccessControlLog (
      Date_Time
	, FolderAccessId
    , InsertEntryLevel
	, MemberId
	, FolderId
	, MemberName
	, FolderPath
)
SELECT
      Date_Time         = SYSDATETIME()
	, FolderAccessId    = o.FolderAccessId
    , InsertEntryLevel  = 2
	, MemberId          = o.MemberId
	, FolderId          = o.FolderId
	, MemberName        = m.name
	, FolderPath        = f.path
FROM #Output o (NOLOCK)
JOIN #member m (NOLOCK)
    ON o.MemberId = m.id
JOIN #Folder f (NOLOCK)
    ON o.FolderId = f.id
OPTION (MAXDOP 2);

SET @Level2Time = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @Level3Time, @Level2Time);
PRINT 'Number of LEVEL 2 rows inserted: ' + CAST(@RowCount as VARCHAR)
    + ', Date/Time: [' + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Insert new entries into FolderAccess
-- Level 1
TRUNCATE TABLE #Output;

INSERT INTO r2w_db.dbo.FolderAccess (
      folderid
    , memberid
    , folderpermission
    , delegationpermission
    , syncpermission
    , propagative
)
OUTPUT
      INSERTED.id
    , INSERTED.memberid
    , INSERTED.folderid
    INTO #Output
SELECT DISTINCT
      folderid             = fppp.id
    , memberid             = ir.MemberId
    , folderpermission     = 'R'
    , delegationpermission = 'N'
    , syncpermission       = 'N'
    , propagative          = 0
FROM #InsertRecords ir
JOIN r2w_db.dbo.folder f (NOLOCK)
    ON f.id = ir.FolderId
JOIN r2w_db.dbo.folder fp (NOLOCK)
    ON f.parentid = fp.id
JOIN r2w_db.dbo.folder fpp (NOLOCK)
	ON fp.parentid = fpp.id
JOIN r2w_db.dbo.folder fppp (NOLOCK)
	ON fpp.parentid = fppp.id
WHERE NOT EXISTS (
    SELECT 1
    FROM r2w_db.dbo.folderaccess fa (NOLOCK)
    WHERE   fa.folderid = fppp.id
        AND fa.memberid = ir.MemberId
)
AND fppp.parentid != 1
OPTION (MAXDOP 2);

-- Log new folderaccess entries into ContentAccessControlLog
SET @RowCount = @@ROWCOUNT;

INSERT INTO r2w_db.Company.ContentAccessControlLog (
      Date_Time
	, FolderAccessId
    , InsertEntryLevel
	, MemberId
	, FolderId
	, MemberName
	, FolderPath
)
SELECT
      Date_Time         = SYSDATETIME()
	, FolderAccessId    = o.FolderAccessId
    , InsertEntryLevel  = 1
	, MemberId          = o.MemberId
	, FolderId          = o.FolderId
	, MemberName        = m.name
	, FolderPath        = f.path
FROM #Output o (NOLOCK)
JOIN #member m (NOLOCK)
    ON o.MemberId = m.id
JOIN #Folder f (NOLOCK)
    ON o.FolderId = f.id
OPTION (MAXDOP 2);

SET @Level1Time = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @Level2Time, @Level1Time);
PRINT 'Number of LEVEL 1 rows inserted: ' + CAST(@RowCount as VARCHAR)
    + ', Date/Time: [' + CAST(SYSDATETIME() AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds';

-- Provide total time script ran for inserts
SET @EndTime = SYSDATETIME();
SELECT @TotalTime = DATEDIFF(millisecond, @StartTime, @EndTime);
SELECT @TimeFormatted = CONVERT(VARCHAR,DATEADD(millisecond,@TotalTime,0),114);
PRINT ' '
PRINT 'END Date/Time: ['
    + CAST(@StartTime AS VARCHAR) + ']'
    + ' Duration = ' + CAST(@TotalTime AS VARCHAR) + ' Milliseconds OR '
    +  CAST(@TimeFormatted AS VARCHAR);

-- Delete temporary tables
If (OBJECT_ID('tempdb..#Output') Is Not Null)
    Drop Table #Output;

If (OBJECT_ID('tempdb..#Folder') Is Not Null)
    Drop Table #Folder;

If (OBJECT_ID('tempdb..#Member') Is Not Null)
    Drop Table #Member;

If (OBJECT_ID('tempdb..#InsertRecords') Is Not Null)
    Drop Table #InsertRecords;
END
GO