#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pushd ${DIR} > /dev/null

    # logging
    echo =================================================================
    echo "Calling codeface  with following arguments:"
    echo "$@"
    echo =================================================================
    echo

    # get parameters from command line
    TMPDIR=$1 # currently ignored
    CASESTUDY=$2
    CFCONF=$3
    CSCONF=$4
    REPOS=$5
    MAILINGLISTS=$6
    RESULTS=$7
    LOGS=$8

    CFDIR="/mnt/codeface"
    CFDATA="/mnt/codeface-data"
    CFEXTRACT="/mnt/codeface-extraction"
    CFGHW="/mnt/GitHubWrapper/build/libs/GitHubGitWrapper-1.0.jar"

    ## create log folder
    mkdir -p ${LOGS}

    pushd $CFDIR

        ## start ID service
        pushd "id_service"
            echo "### " $(date "+%F %T") "Starting ID service" 2>&1 > "${LOGS}/id_service.log"
            nodejs id_service.js ${CFCONF} "info" 2>&1 >> "${LOGS}/id_service.log" &
            IDSERVICE=$!
        popd

        ## run codeface analysis with current tagging set
        codeface -j 11 -l "devinfo" run --recreate -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${REPOS} > ${LOGS}/codeface_run.log 2>&1

        ## run mailing-list analysis (attached to feature/proximity analysis!)
        # codeface -j 2 -l "devinfo" ml -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1
        codeface -j 11 -l "devinfo" ml --use-corpus -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1

        ## run GitHubWrapper extraction
        java -Xmx8G -jar ${CFGHW} ${CASESTUDY} ${RESULTS} ${REPOS} "${CFDATA}/configurations/tokens/tokens.txt"

        # run extraction process for this configuration
        pushd "${CFEXTRACT}" > /dev/null
            ISSUEPROCESS="${CFEXTRACT}/run-issues.py"
            python ${ISSUEPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_issues.log 2>&1

            EXTRACTION="${CFEXTRACT}/run-extraction.py"
            python ${EXTRACTION} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_extraction.log 2>&1

            MBOXPARSING="${CFEXTRACT}/run-parsing.py"
            # MboxParsing without filepath
            python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${MAILINGLISTS} > ${LOGS}/codeface_mbox_parsing.log 2>&1
            # MboxParsing with filepath
            python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} -f ${RESULTS} ${MAILINGLISTS} > ${LOGS}/codeface_mbox_parsing.log 2>&1
        popd

        ## stop ID service
        kill $IDSERVICE

    popd

popd > /dev/null