#!/usr/bin/env bash

function _USAGE
{
cat << EOF
Usage :
    ${_SCRIPT_NAME} [OPTIONS]

Options :
    -u  website_url     website url (ex: http://mydomain.ovh)
    -d  documentroot    documentroot directory relative to home directory (ex: www)
    -e  entrypoint      entrypoint (ex: app.py, index.js, config.ru)
    -p  publicdir       publicdir directory relative to documentroot (ex: public)
    -h                  show this message
Ex :
    ${_SCRIPT_NAME} -u http://mydomain.ovh -d www -e app.py -p public

EOF
exit 1
}

function _LOGS
{
    local _LEVEL="${1}"
    local _MESSAGE="${2}"
    local _DATE="$(date --iso-8601=seconds)"
    local _LOGS_MESSAGE="[${_DATE}]  ${_LEVEL} ${_MESSAGE}"
    echo -e "${_LOGS_MESSAGE}"
}

function _GET_OPTS
{
    local _SHORT_OPTS="u:d:e:p:h";
    local _OPTS=$(getopt \
        -o "${_SHORT_OPTS}" \
        -n "${_SCRIPT_NAME}" -- "${@}")

    eval set -- "${_OPTS}"

    while true ; do
        case "${1}" in
            -u)
                _URL_OPT=${2}
                shift 2
                ;;
            -d)
                _DOCUMENTROOT_OPT=${2}
                shift 2
                ;;
            -e)
                _ENTRYPOINT_OPT=${2}
                shift 2
                ;;
            -p)
                _PUBLICDIR_OPT=${2}
                shift 2
                ;;
            -h|--help)
                _USAGE
                shift
                ;;
            --) shift ; break ;;
        esac
    done
}

function _CHECK_OPTS
{
    if [ -z "${_DOCUMENTROOT_OPT}" ]
    then
        _LOGS "ERROR" "documentroot cannot be empty"
        exit 1
    fi
    if [ -z "${_URL_OPT}" ]
    then
        _LOGS "ERROR" "website_url cannot be empty"
        exit 1
    fi
    if [ -z "${_ENTRYPOINT_OPT}" ]
    then
        _LOGS "ERROR" "entrypoint cannot be empty"
        exit 1
    fi
    if [ -z "${_PUBLICDIR_OPT}" ]
    then
        _LOGS "ERROR" "publicdir cannot be empty"
        exit 1
    fi

    if [ -z "${HOME}" ]
    then
        _LOGS "ERROR" "home env var empty stopping"
        exit 1
    fi
}

function _LOAD_ENV
{
    source /etc/ovhconfig.bashrc
    passengerConfig
}

function _PRINT_ENV
{
    cat << EOF
==============================================================
OVH_APP_ENGINE=${OVH_APP_ENGINE}
OVH_APP_ENGINE_VERSION=${OVH_APP_ENGINE_VERSION}
OVH_ENVIRONMENT=${OVH_ENVIRONMENT}
PATH=${PATH}
==============================================================
EOF
}

function _REMOVING_OLD_DOCUMENTROOT
{
    _LOGS "INFO" "removing old documentroot"
    rm -rf "${HOME:?}"/"${_DOCUMENTROOT_OPT}"
}

function _CLONING_OVH_DOCS_RENDERING
{
    local _OVH_DOCS_RENDERING_REPOSITORY=${OVH_DOCS_RENDERING_REPOSITORY:=https://github.com/ovh/docs-rendering.git}
    local _OVH_DOCS_RENDERING_BRANCH=${OVH_DOCS_RENDERING_BRANCH:=master}
    _LOGS "INFO" "cloning ovh docs rendering repository"
    git clone --recurse-submodules "${_OVH_DOCS_RENDERING_REPOSITORY}" --single-branch --branch "${_OVH_DOCS_RENDERING_BRANCH}" "${HOME}"/"${_DOCUMENTROOT_OPT}"
}

function _ADDING_REQUIREMENTS
{
    _LOGS "INFO" "adding custom requirements"
    cat << 'EOF' >> "${HOME}"/"${_DOCUMENTROOT_OPT}"/requirements.txt
flask==1.1.2
GitPython==3.1.13
EOF
}

function _CREATING_VIRTUALENV
{
   _LOGS "INFO" "creating virtualenv"
   virtualenv "${HOME}"/"${_DOCUMENTROOT_OPT}"/venv
   source "${HOME}"/"${_DOCUMENTROOT_OPT}"/venv/bin/activate
}

function _UPGRADE_VIRTUALENV_PIP
{
    _LOGS "INFO" "upgrading virtualenv pip"
    pip install --upgrade pip
}

function _INSTALLING_REQUIREMENTS
{
    _LOGS "INFO" "installing requirements"
    pip install -r "${HOME}"/"${_DOCUMENTROOT_OPT}"/requirements.txt
}

function _CLONING_OVH_DOCS
{
    local _OVH_DOCS_REPOSITORY=${OVH_DOCS_REPOSITORY:=https://github.com/ovh/docs.git}
    local _OVH_DOCS_BRANCH=${OVH_DOCS_BRANCH:=master}
    _LOGS "INFO" "cloning ovh docs repository"
    git clone "${_OVH_DOCS_REPOSITORY}" --single-branch --branch "${_OVH_DOCS_BRANCH}" "${HOME}"/"${_DOCUMENTROOT_OPT}"/ovhdocs
}

function _PELICAN
{
    _LOGS "INFO" "build static pages"
    cd "${HOME}"/"${_DOCUMENTROOT_OPT}"
    #pelican "${HOME}"/"${_DOCUMENTROOT_OPT}"/ovhdocs/pages -o "${HOME}"/"${_DOCUMENTROOT_OPT}"/"${_PUBLICDIR_OPT}" -s "${HOME}"/"${_DOCUMENTROOT_OPT}"/pelicanconf.py --fatal errors
    pelican "${HOME}"/"${_DOCUMENTROOT_OPT}"/ovhdocs/pages -o "${HOME}"/"${_DOCUMENTROOT_OPT}"/"${_PUBLICDIR_OPT}" -s "${HOME}"/"${_DOCUMENTROOT_OPT}"/pelicanconf.py
}

function _CREATING_ENTRYPOINT
{
    _LOGS "INFO" "creating entrypoint"
    cat << EOF > "${HOME}"/"${_DOCUMENTROOT_OPT}"/"${_ENTRYPOINT_OPT}"
this_file = "venv/bin/activate_this.py"
exec(open(this_file).read(), {"__file__": this_file})

from flask import Flask, send_from_directory, redirect, Response
from werkzeug.exceptions import NotFound
import git
import sys
import time
import json


LOADED = time.strftime("%s")
application = Flask(__name__, static_folder="${_PUBLICDIR_OPT}")


@application.route("/")
def default_fr():
    return redirect("/fr/")


@application.route("/about")
def about():
    loaded = LOADED
    uptime = int(time.strftime("%s")) - int(loaded)
    ovhdocs = git.Repo("ovhdocs")
    ovhdocsrendering = git.Repo(".")
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    aboutjs = {
            "build": "$(date +%s)",
            "loaded": f"{loaded}",
            "uptime": f"{uptime}",
            "python": f"{python_version}",
            "ovhdocsrendering": {
                "url": f"{ovhdocsrendering.remotes.origin.url}",
                "branch": f"{ovhdocsrendering.head.ref}",
                "commit": f"{ovhdocsrendering.head.commit}"
            },
            "ovhdocs": {
                "url": f"{ovhdocs.remotes.origin.url}",
                "branch": f"{ovhdocs.head.ref}",
                "commit": f"{ovhdocs.head.commit}"
            }
    }
    return Response(json.dumps(aboutjs), mimetype="application/json")


@application.route("/<path:path>")
def serve_static(path):
    try:
        return send_from_directory(application.static_folder, path)
    except NotFound as e:
        if path.endswith("/"):
            return send_from_directory(application.static_folder, path + "index.html")
        raise e
EOF
}

function _RESTARTING
{
    _LOGS "INFO" "restarting"
    mkdir -p "${HOME}"/"${_DOCUMENTROOT_OPT}"/tmp
    touch "${HOME}"/"${_DOCUMENTROOT_OPT}"/tmp/restart.txt
}

function _SLEEPING
{
    _LOGS "INFO" "wait 30s for NFS file propagation"
    sleep 30
}

### MAIN
set -e
set -o pipefail
_SCRIPT_NAME=$(basename "${0}")
_GET_OPTS "${@}"
_CHECK_OPTS
_LOAD_ENV
_PRINT_ENV
_REMOVING_OLD_DOCUMENTROOT
_CLONING_OVH_DOCS_RENDERING
_ADDING_REQUIREMENTS
_CREATING_VIRTUALENV
_UPGRADE_VIRTUALENV_PIP
_INSTALLING_REQUIREMENTS
_CLONING_OVH_DOCS
_PELICAN
_CREATING_ENTRYPOINT
_RESTARTING
_SLEEPING
_LOGS "INFO" "job is done"
