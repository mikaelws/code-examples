#!/bin/sh

#  createreleaseinfo.sh
#  Release Workflow
#
#  Created by Sikora, Mikael (DS) on 6/20/2012
#
#  This script creates Confluece Release pages from Jira "Release Request" issues 
#  that have "Create Release Page Status" set to "Pending"

# Set DEBUG mode for displaying constant and variable information
#  DEBUG="ON"

# Driver:  Call the functions
# ---------------------------
driver () {
    SetEnvironment
    InitJiraConstants
    InitializeCLI
    ManageFiles
    GetPendingIssues
    InitialMessages
    CreateReleasePages
    Finish
}

# Called Functions
# ================

SetEnvironment () {
#    ENVIRONMENT="Local"
#    ENVIRONMENT="Mock"
    ENVIRONMENT="Prod"

    echo
    echo "ENVIRONMENT = $ENVIRONMENT"
    echo
}

InitJiraConstants () {

    JIRA_TEMP_FILE=/tmp/.jiraissuetmp
    PROJECT_NAME="CM/RM" 

    # Confluence Status Fields in JIRA
    CREATED_FIELD="Created"                      # customfieldvalue.stringvalue
    PENDING_FIELD="Pending"                      # customfieldvalue.stringvalue
    STATUS_FIELD="Release Page Creation Status"  # customfield.cfname

    # JIRA fields for populating release page
    JIRA_FIELD_NAME_ARRAY=(
        "Branch Integrity Link" 
        "Bug List Link" 
        "CDCC Component" 
        "Code Freeze Date" 
        "Create Branch Date" 
        "DB Components" 
        "Dependency Notification Date" 
        "Deployment Plan Link" 
        "Deployment Plan Review Date/Time" 
        "Go/No-Go Checklist Link"
        "Go/No-Go Date/Time" 
        "IT Outage Request Link" 
        "KIR2 End Date" 
        "KIR2 Start Date"
        "Mock Date/Time" 
        "Mock End Date" 
        "Other Components"
        "Outage State"
        "Perf Test End Date"
        "Perf Test Start Date"
        "QA Deploy Date"
        "QA Environment" 
        "QA Verified Date"        
        "Release Date/Time" 
        "Release Name" 
        "Release Major Deliverables" 
        "Release Notes Date" 
        "Release Parent Page"
        "Release Readiness Date 1" 
        "Release Readiness Date 2"
        "Release Readiness Date 3" 
        "Release Readiness Link"
        "Release Page Template"
    )
}

InitializeCLI () {
    # Initialize CONFLUENCE and JIRA CLI executables
    CONFLUENCE=/usr/local/confluence-cli/confluence.sh
    JIRA=/usr/local/jira-cli/jira.sh

    # Initialize CONFLUENCE and JIRA CLI logins
    case "$ENVIRONMENT" in
        "Local")
            CONFLUENCE_LOGIN="--user automation --password xxxxxxxxxx --server http://localhost:8070"
            JIRA_LOGIN="--user automation --password xxxxxxxxxx --server http://localhost:8080"
            PROJECT_KEY="RM-"
        ;;
        "Mock")
            CONFLUENCE_LOGIN="--user cmbuild --password Xxxxx#xx --server https://confluence.company.com"
            JIRA_LOGIN="--user cmbuild --password Xxxxx#xx --server http://dev02.savvis.company.com:8080"
            PROJECT_KEY="CORECMRM-"
        ;;
        "Prod")
            CONFLUENCE_LOGIN="--user cmbuild --password Xxxxx#xx --server https://confluence.company.com"
            JIRA_LOGIN="--user cmbuild --password Xxxxx#xx --server https://jira.company.com"
            PROJECT_KEY="CORECMRM-"
        ;;
    esac
}

ManageFiles () {
    if [ -f "$JIRA_TEMP_FILE" ] ; then
        rm $JIRA_TEMP_FILE
    fi
}

GetPendingIssues () {
    # Get the issue numbers that are 'pending release page creation' (on one line seperated by space)
    # Dump the issue numbers into a temporary file
    $JIRA $JIRA_LOGIN --action getIssueList --search "project = '$PROJECT_NAME' and '$STATUS_FIELD' = '$PENDING_FIELD'" --outputFormat 4 --file "$JIRA_TEMP_FILE"

    # If temporary file exists, delete quotes, read record, match project key to first field, place
    # project key into temporary variable, then replace commas with spaces, finally write out to
    # issuePkeyList ending with a carriage return.
    # NOTE:  Improve readability by breaking each step into it's own line with comments.
    if [ -f "$JIRA_TEMP_FILE" ] ; then
        issuePkeyList=$(awk -F',' -v ORS=" " -v aVar=$PROJECT_KEY 'match($1,aVar) {print $1;} END { printf("\n"); }' $JIRA_TEMP_FILE | tr -d '"')
    fi
    echo

    # Load issue number list into array
    issuePkeyArray=($issuePkeyList)
}

InitialMessages () {
    if [ "$DEBUG" ] ; then
        echo "DEBUG MODE is ON"
        echo
        echo "JIRA FIELDS"
        j=0
        for i in "${JIRA_FIELD_NAME_ARRAY[@]}"; do # echoes one line for each element of the array.
            echo "  JIRA_FIELD_NAME_ARRAY[$j]:  $i"
            ((j++))
        done
        echo
    fi

    echo "  Issue number(s):  ${issuePkeyArray[@]}"
    echo
}

CreateReleasePages () {
    # Read each Issue data and create Confluence page
    if [ "$issuePkeyArray" = "" ] ; then
        echo "No issues are pending page creation."
    else
        echo "CREATING RELEASE PAGES.  This may take a minute or two..."
        echo

        # READ JIRA ISSUE FIELDS FOR PAGE CREATION VALUES
        # Iterate through Issue array
        for issuePkey in "${issuePkeyArray[@]}"
        do 
            if [ "$DEBUG" ] ; then
                echo "CREATE RELEASE PAGE"
                echo "-------------------"
                echo "ISSUE PKEY:    $issuePkey"
                echo
            fi

            # Call functions for each issue
            GetFieldValues
            PopulateConfluenceVariables
            ScrubFields
            CreateConfluencePage
        done
    fi
}

GetFieldValues () {
    jiraFieldValueArray=""
    index=0

    if [ "$DEBUG" ] ; then
        echo "GET FIELD VALUES"
        echo "----------------"
    fi

    for fieldValue in "${JIRA_FIELD_NAME_ARRAY[@]}" ; do 

        if [ "$DEBUG" ] ; then
            echo "  INDEX = $index"
            echo "    Field Name:  ${JIRA_FIELD_NAME_ARRAY[$index]}"
        fi

        jiraFieldValueArray[$index]=$($JIRA $JIRA_LOGIN --action getFieldValue --issue "$issuePkey" --field "${JIRA_FIELD_NAME_ARRAY[$index]}" | sed -n '2,$p')

        if [ "$DEBUG" ] ; then
            echo "      jiraFieldValueArray[$index]:  ${jiraFieldValueArray[$index]}"
            echo
        fi
        ((index++))  
    done
}

PopulateConfluenceVariables () {
    # Listed in same order as JIRA_FIELD_NAME_ARRAY
    branchIntegrityLink=${jiraFieldValueArray[0]}     # Branch Integrity Link
    bugListLink=${jiraFieldValueArray[1]}             # Bug List Link
    cdccComponent=${jiraFieldValueArray[2]}           # CDCC Component
    codeFreezeDate=${jiraFieldValueArray[3]}          # Code Freeze Date
    createBranchDate=${jiraFieldValueArray[4]}        # Create Branch Date
    dbComponents=${jiraFieldValueArray[5]}            # DB Components
    dependencyNotificationDate=${jiraFieldValueArray[6]}  # Dependency Notification Date
    deploymentPlanLink=${jiraFieldValueArray[7]}      # Deployment Plan Link
    deploymentPlanReviewDateTime=${jiraFieldValueArray[8]}  # Deployment Plan Review Date/Time
    goNoGoChecklistLink=${jiraFieldValueArray[9]}     # Go/No-Go Checklist Link
    goNoGoDateTime=${jiraFieldValueArray[10]}         # Go/No-Go Date/Time
    itOutageRequestLink=${jiraFieldValueArray[11]}    # IT Outage Request Link
    kir2EndDate=${jiraFieldValueArray[12]}            # KIR2 End Date
    kir2StartDate=${jiraFieldValueArray[13]}          # KIR2 Start Date
    mockDateTime=${jiraFieldValueArray[14]}           # Mock Date/Time
    mockEndDate=${jiraFieldValueArray[15]}            # Mock End Date
    otherComponents=${jiraFieldValueArray[16]}        # Other Components
    outageStatus=${jiraFieldValueArray[17]}           # Outage State
    perfTestEndDate=${jiraFieldValueArray[18]}        # Perf Test End Date
    perfTestStartDate=${jiraFieldValueArray[19]}      # Perf Test Start Date
    qaDeployDate=${jiraFieldValueArray[20]}           # QA Deploy Date
    qaEnvironment=${jiraFieldValueArray[21]}          # QA Environment
    qaVerifiedDate=${jiraFieldValueArray[22]}         # QA Verified Date
    releaseDateTime=${jiraFieldValueArray[23]}        # Release Date/Time
    releasePageTitle=${jiraFieldValueArray[24]}       # Release Name
    releaseMajorDeliverables=${jiraFieldValueArray[25]}  # Release Major Deliverables
    releaseNotesDate=${jiraFieldValueArray[26]}       # Release Notes Date
    parentPage=${jiraFieldValueArray[27]}             # Release Parent Page
    releaseReadinessDate1=${jiraFieldValueArray[28]}  # Release Readiness Date 1
    releaseReadinessDate2=${jiraFieldValueArray[29]}  # Release Readiness Date 2
    releaseReadinessDate3=${jiraFieldValueArray[30]}  # Release Readiness Date 3
    releaseReadinessLink=${jiraFieldValueArray[31]}   # Release Readiness Link
    templateTitle=${jiraFieldValueArray[32]}          # Release Page Template

    if [ "$DEBUG" ] ; then
        # Listed in same order as JIRA_FIELD_NAME_ARRAY
        echo "CONFLUENCE VARIABLES POPULATED AS SUCH"
        echo "  branchIntegrityLink           $branchIntegrityLink"
        echo "  bugListLink:                  $bugListLink"
        echo "  cdccComponent:                $cdccComponent"
        echo "  codeFreezeDate:               $codeFreezeDate"
        echo "  createBranchDate:             $createBranchDate"
        echo "  dbComponents:                 $dbComponents"
        echo "  dependencyNotificationDate:   $dependencyNotificationDate"
        echo "  deploymentPlanLink:           $deploymentPlanLink"
        echo "  deploymentPlanReviewDateTime: $deploymentPlanReviewDateTime"
        echo "  goNoGoChecklistLink:          $goNoGoChecklistLink"
        echo "  goNoGoDateTime:               $goNoGoDateTime"
        echo "  itOutageRequestLink:          $itOutageRequestLink"
        echo "  kir2EndDate:                  $kir2EndDate"
        echo "  kir2StartDate:                $kir2StartDate"
        echo "  mockDateTime:                 $mockDateTime"
        echo "  mockEndDate:                  $mockEndDate"
        echo "  otherComponents:              $otherComponents"
        echo "  outageStatus:                 $outageStatus"
        echo "  perfTestEndDate:              $perfTestEndDate"
        echo "  perfTestStartDate:            $perfTestStartDate"
        echo "  qaDeployDate:                 $qaDeployDate"
        echo "  qaEnvironment:                $qaEnvironment"
        echo "  qaVerifiedDate:               $qaVerifiedDate"
        echo "  releaseDateTime:              $releaseDateTime"
        echo "  releasePageTitle:             $releasePageTitle" # Release Name
        echo "  releaseMajorDeliverables      $releaseMajorDeliverables"
        echo "  releaseNotesDate              $releaseNotesDate"
        echo "  parentPage:                   $parentPage"       # Release Parent Page
        echo "  releaseReadinessDate1:        $releaseReadinessDate1"
        echo "  releaseReadinessDate2:        $releaseReadinessDate2"
        echo "  releaseReadinessDate3:        $releaseReadinessDate3"
        echo "  releaseReadinessLink          $releaseReadinessLink"
        echo "  templateTitle:                $templateTitle"
        echo
    fi
}

ScrubFields () {
    # remove 'http://' or 'https://' from links
    branchIntegrityLink=$(echo $branchIntegrityLink | sed -e 's|http://||')
    bugListLink=$(echo $bugListLink | sed -e 's|http://||')
    deploymentPlanLink=$(echo $deploymentPlanLink | sed -e 's|https://||')
    goNoGoChecklistLink=$(echo $goNoGoChecklistLink | sed -e 's|https://||')
    itOutageRequestLink=$(echo $itOutageRequestLink | sed -e 's|http://||')
    releaseReadinessLink=$(echo $releaseReadinessLink | sed -e 's|https://||')

    # Replace linefeed w/ semi-colon and space.  (Linefeed doesn't transfer)
    # Take out single quotes passed in from JIRA
    # Append single quote at beginning and end to allow inputted puncitonation
    releaseMajorDeliverables=$(echo "$releaseMajorDeliverables" | tr '\n' ';'  | sed 's/[;]*$//' | sed 's/[;]/; /g' | sed -e s/\'//g | sed -e s/^/\'/ -e s/$/\'/)

    # Take out single quotes passed in from JIRA
    # Quote text to allow entries with commas
    if [ "$cdccComponent" ] ; then
        cdccComponent=$(echo $cdccComponent | sed -e s/\'//g | sed -e s/^/\'/ -e s/$/\'/)
    fi
    if [ "$dbComponents" ] ; then
        dbComponents=$(echo $dbComponents | sed -e s/\'//g | sed -e s/^/\'/ -e s/$/\'/)
    fi
    if [ "$otherComponents" ] ; then
        otherComponents=$(echo $otherComponents | sed -e s/\'//g | sed -e s/^/\'/ -e s/$/\'/)
    fi


    # If dateTime exists, add single quote to allow usage of colon, else 'N/A'
    if [ "$deploymentPlanReviewDateTime" ] ; then
        deploymentPlanReviewDateTime=$(echo $deploymentPlanReviewDateTime | sed -e s/^/\'/ -e s/$/\'/)
    else
        deploymentPlanReviewDateTime="N/A"
    fi
    if [ "$mockDateTime" ] ; then
        mockDateTime=$(echo $mockDateTime | sed -e s/^/\'/ -e s/$/\'/)
    else
        mockDateTime="N/A"
    fi
    if [ "$goNoGoDateTime" ] ; then
        goNoGoDateTime=$(echo $goNoGoDateTime | sed -e s/^/\'/ -e s/$/\'/)
    else
        goNoGoDateTime="N/A"
    fi
    if [ "$releaseDateTime" ] ; then
        releaseDateTime=$(echo $releaseDateTime | sed -e s/^/\'/ -e s/$/\'/)
    else
        releaseDateTime="TBD"
    fi
    
    # Replace other blank dates with 'N/A'
    if [ -z "$codeFreezeDate" ] ; then
        codeFreezeDate="N/A"
    fi
    if [ -z "$createBranchDate" ] ; then
        createBranchDate="N/A"
    fi
    if [ -z "$dependencyNotificationDate" ] ; then
        dependencyNotificationDate="N/A"
    fi
    if [ -z "$kir2EndDate" ] ; then
        kir2EndDate="N/A"
    fi
    if [ -z "$kir2StartDate" ] ; then
        kir2StartDate="N/A"
    fi
    if [ -z "$mockEndDate" ] ; then
        mockEndDate="N/A"
    fi
    if [ -z "$perfTestEndDate" ] ; then
        perfTestEndDate="N/A"
    fi
    if [ -z "$perfTestStartDate" ] ; then
        perfTestStartDate="N/A"
    fi
    if [ -z "$qaDeployDate" ] ; then
        qaDeployDate="N/A"
    fi
    if [ -z "$qaVerifiedDate" ] ; then
        qaVerifiedDate="N/A"
    fi
    if [ -z "$releaseNotesDate" ] ; then
        releaseNotesDate="N/A"
    fi
    if [ -z "$releaseReadinessDate1" ] ; then
        releaseReadinessDate1="N/A"
    fi
    if [ -z "$releaseReadinessDate2" ] ; then
        releaseReadinessDate2="N/A"
    fi
    if [ -z "$releaseReadinessDate3" ] ; then
        releaseReadinessDate3="N/A"
    fi

    if [ "$DEBUG" ] ; then
        echo "SCRUB FIELDS"
        echo "  branchIntegrityLink:                    $branchIntegrityLink"
        echo "  bugListLink truncated:                  $bugListLink"
        echo "  deploymentPlanLink truncated:           $deploymentPlanLink"
        echo "  goNoGoChecklistLink truncated:          $goNoGoChecklistLink"
        echo "  itOutageRequestLink truncated:          $itOutageRequestLink"
        echo "  releaseReadinessLink                    $releaseReadinessLink"
        echo "  releaseMajorDeliverables replace newline w/ semi-colon:    $releaseMajorDeliverables"
        echo "  deploymentPlanReviewDateTime:           $deploymentPlanReviewDateTime"
        echo "  mockDateTime quotes added:              $mockDateTime"
        echo "  releaseDateTime quotes added:           $releaseDateTime"
        echo "  codeFreezeDate:                         $codeFreezeDate"
        echo "  createBranchDate:                       $createBranchDate"
        echo "  dependencyNotificationDate:             $dependencyNotificationDate"
        echo "  kir2EndDate:                            $kir2EndDate"
        echo "  kir2StartDate:                          $kir2StartDate"
        echo "  mockEndDate:                            $mockEndDate"
        echo "  perfTestEndDate:                        $perfTestEndDate"
        echo "  perfTestStartDate:                      $perfTestStartDate"
        echo "  qaDeployDate:                           $qaDeployDate"
        echo "  qaVerifiedDate:                         $qaVerifiedDate"
        echo "  releaseNotesDate:                       $releaseNotesDate"
        echo "  releaseReadinessDate1:                  $releaseReadinessDate1"
        echo "  releaseReadinessDate2:                  $releaseReadinessDate2"
        echo "  releaseReadinessDate3:                  $releaseReadinessDate3"
        echo
    fi
}

CreateConfluencePage () {
    echo "  Creating release page: $releasePageTitle" 
    echo

    # MATCH CONFLUENCE FIELDS WITH JIRA FIELDS
    # Listed in same order as JIRA_FIELD_NAME_ARRAY
    FIND_REPLACE_STRING="
        BranchIntegrity:$branchIntegrityLink,
        BugListLink:$bugListLink,
        *CDCCComponent:$cdccComponent,
        *CodeFreezeDate:$codeFreezeDate,
        *CreateBranchDate:$createBranchDate,
        *DBComponents:$dbComponents,
        *DependencyNotificationDate:$dependencyNotificationDate,
        DeploymentPlanLink:$deploymentPlanLink,
        *DeploymentPlanReviewDateTime:$deploymentPlanReviewDateTime,
        GoNoGoChecklistLink:$goNoGoChecklistLink,
        *GoNoGoDateTime:$goNoGoDateTime,
        ITOutageRequestLink:$itOutageRequestLink,
        *KIR2EndDate:$kir2EndDate,
        *KIR2StartDate:$kir2StartDate,
        *Scope:$releaseMajorDeliverables,
        *MockDateTime:$mockDateTime,
        *MockEndDate:$mockEndDate,
        *OtherComponent:$otherComponents,
        *OutageStatus:$outageStatus,
        *PerfTestEndDate:$perfTestEndDate,
        *PerfTestStartDate:$perfTestStartDate,
        *QADeploymentDate:$qaDeployDate,
        *QAEnvironment:$qaEnvironment,
        *QAVerifiedDate:$qaVerifiedDate,
        *ReleaseNotesDate:$releaseNotesDate,
        *ReleaseDateTime:$releaseDateTime,
        *ReleaseReadinessDate1:$releaseReadinessDate1,
        *ReleaseReadinessDate2:$releaseReadinessDate2,
        *ReleaseReadinessDate3:$releaseReadinessDate3,
        ReleaseReadiness:$releaseReadinessLink
    "

    if [ "$DEBUG" ] ; then
        echo "  FIND_REPLACE_STRING:  $FIND_REPLACE_STRING"
        echo
        echo "  CREATING RELEASE PAGE"
        echo
    fi

    # CREATE THE RELEASE PAGE
    cmdMessage=$(($CONFLUENCE $CONFLUENCE_LOGIN --action copyPage --space "DEV" --title "$templateTitle" --newTitle "$releasePageTitle" --parent "$parentPage" --copyAttachments --findReplace "$FIND_REPLACE_STRING") 2>&1)

    if [ $? != 0 ] ; then
        echo "    PAGE CREATION ERROR: Problem creating '$releasePageTitle' in '$parentPage'"
        echo "    ERROR MESSAGE:  $cmdMessage"
        echo

        # CHECK THAT RELEASE PAGE STATUS IS UPDATED TO "CREATED" OR REMAINS "PENDING"
        echo "    POST-UPDATE STATUS:  $($JIRA $JIRA_LOGIN --action getFieldValue --issue "$issuePkey" --field "$STATUS_FIELD")"
        echo
    else
        echo "    PAGE CREATION SUCCESSFUL.  CREATION MESSAGE:  $cmdMessage"
        echo

        # Call Function to set 'Page Created' flag
        SetCreatedFlag
    fi
}

SetCreatedFlag () {
    # CHECK CURRENT FLAG STATUS
    if [ "$DEBUG" ] ; then
        echo "  Set STATUS flag from 'PENDING' to 'CREATED' on field: $STATUS_FIELD"
        echo
        echo "    PRE-UPDATE STATUS:  $($JIRA  $JIRA_LOGIN --action getFieldValue --issue "$issuePkey" --field "$STATUS_FIELD")"
        echo
    fi

    # SET 'Page Creation Flag' TO 'Created'
    $JIRA  $JIRA_LOGIN --action updateIssue --issue "$issuePkey" --custom "$STATUS_FIELD:$CREATED_FIELD"
    echo

    # CHECK THAT RELEASE PAGE STATUS IS UPDATED TO "Created" OR REMAINS "Pending"
    echo "    POST-UPDATE STATUS:  $($JIRA $JIRA_LOGIN --action getFieldValue --issue "$issuePkey" --field "$STATUS_FIELD")"
    echo
}

Finish () {
    echo "------------------------"
    echo "Finshed creating page(s)"
}

# Drive the functions
driver

exit 0
