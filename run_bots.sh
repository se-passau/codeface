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
    CFGHW="/mnt/GitHubWrapper/build/libs/GitHubWrapper-1.0-SNAPSHOT.jar"
    BODEGHA="/mnt/bodegha/bodegha"
    TITAN="${CFDIR}/titan"

    ## create log folder
    mkdir -p ${LOGS}

    pushd $CFDIR

        ## start ID service
        pushd "id_service"
            echo "### " $(date "+%F %T") "Starting ID service" 2>&1 > "${LOGS}/id_service.log"
            nodejs id_service.js ${CFCONF} "info" 2>&1 >> "${LOGS}/id_service.log" &
            IDSERVICE=$!
        popd

        # ## set stack size large enough to prevent C stack overflow errors
        # ulimit -s 512000
        # ## run codeface analysis with current tagging set
        # codeface -j 11 -l "devinfo" run --recreate -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${REPOS} > ${LOGS}/codeface_run.log 2>&1

        # ## run mailing-list analysis (attached to feature/proximity analysis!)
        # codeface -j 11 -l "devinfo" ml -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1
        # #codeface -j 11 -l "devinfo" ml --use-corpus -c ${CFCONF} -p ${CSCONF} "${RESULTS}" "${MAILINGLISTS}" > ${LOGS}/codeface_ml.log 2>&1

        # ## run conway analysis (do NOT give -j paramater, it may break the analysis!)
        # unset DISPLAY
        # codeface -l "devinfo" conway -c ${CFCONF} -p ${CSCONF} "${RESULTS}" ${REPOS} ${TITAN} > ${LOGS}/codeface_conway.log 2>&1

        # ## run GitHubWrapper extraction
        # mkdir -p "${RESULTS}/${CASESTUDY}_issues/"
        # java -Xmx250G -Xss1G -jar "${CFGHW}" \
        #     -dump "${RESULTS}/${CASESTUDY}_issues/issues.json" \
        #     -tokens "${CFDATA}/configurations/tokens.txt" \
        #     -repo "${REPOS}/${CASESTUDY}/" \
        #     -workDir "${REPOS}/" > ${LOGS}/codeface_githubwrapper.log 2>&1

        ## run BoDeGHa to identify bots on GitHub
        source "${BODEGHA}/bin/activate"
        pushd "${REPOS}/${CASESTUDY}/" > /dev/null
            URL=$(git remote get-url origin)
            URL_WITHOUT_SUFFIX=${URL%.*}
            REPO_NAME=$(basename ${URL%.*})
            REPO_ORGANIZATION=$(basename "${URL_WITHOUT_SUFFIX%/${REPO_NAME}}")
        popd
        TOKEN=$(tail -n 1 "${CFDATA}/configurations/tokens.txt")
        # TODO: start date?
        BODEGHA_COMMAND="bodegha ${REPO_ORGANIZATION}/${REPO_NAME} --verbose --key ${TOKEN} --csv --start-date 01-01-2009 --max-comments 2000"
        BODEGHA_LOG="${LOGS}/codeface_bodegha.log"
        echo ${BODEGHA_COMMAND} > ${BODEGHA_LOG}
        ${BODEGHA_COMMAND} 2>> ${BODEGHA_LOG} 1> "${RESULTS}/${CASESTUDY}_issues/bots.csv"
        deactivate

        ## run extraction process for this configuration
        pushd "${CFEXTRACT}" > /dev/null
            ISSUEPROCESS="${CFEXTRACT}/run-issues.py"
            python ${ISSUEPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_issues.log 2>&1

            # ISSUEPROCESS="${CFEXTRACT}/run-jira-issues.py"
            # python ${ISSUEPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_issues_jira.log 2>&1

            BOTSPROCESS="${CFEXTRACT}/run-bots.py"
            python ${BOTSPROCESS} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_bots.log 2>&1

            EXTRACTION="${CFEXTRACT}/run-extraction.py"
            ## Remove already existing backup folder (to be able to create a new backup in the author postprocessing step
            CSTAGGING=$(basename ${CSCONF} .conf)
            rm -rf "${RESULTS}/${CSTAGGING}/${CSTAGGING##*_}_bak/"
            python ${EXTRACTION} -c ${CFCONF} -p ${CSCONF} ${RESULTS} > ${LOGS}/codeface_extraction.log 2>&1
            # add parameter '--range' to run extractions also for all ranges
            # add parameter '--implementation' to extract function implementations
            # add parameter '--commit-messages' to extract commit messages

            AUTHORPOSTPROCESS="${CFEXTRACT}/run-author-postprocessing.py"
            python ${AUTHORPOSTPROCESS} -c ${CFCONF} -p ${CSCONF} --backup ${RESULTS} > ${LOGS}/codeface_author_postprocessing.log 2>&1

            # MBOXPARSING="${CFEXTRACT}/run-parsing.py"
            # ## Remove already existing log file to be able to append later
            # rm ${LOGS}/codeface_mbox_parsing.log
            # ## MboxParsing without filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing with filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} -f ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing file (base name only)
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} --file ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
            # ## MboxParsing file with filepath
            # python ${MBOXPARSING} -c ${CFCONF} -p ${CSCONF} --file -f ${RESULTS} ${MAILINGLISTS} >> ${LOGS}/codeface_mbox_parsing.log 2>&1
        popd

        ## stop ID service
        kill $IDSERVICE

    popd

popd > /dev/null