#!/bin/bash

# Для IW_PARAMETERIZED_INSTALLATION
function usage() {
    echo "This script must be run with super-user privileges."
    echo -e "\nUsage: $0 [arguments]"
    echo -e "\nArguments:"
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        echo "  f - [required] Install or update ${DLP_PRODUCT_NAME}. Values: 'i' to install ${DLP_AGENT_SERVER}, 'uf' to update ${DLP_WEB_UI}, 'ub' to update ${DLP_AGENT_SERVER}, 'ua' to update both ${DLP_WEB_UI} and ${DLP_AGENT_SERVER}"
    else
        echo "  f - [required] Install ${DLP_PRODUCT_NAME}. Values: 'i' to install ${DLP_AGENT_SERVER}"
    fi
    echo "  l - [optional] ${DLP_AGENT_SERVER} language. Values: 'r' for Russian or 'e' for English. Default value is 'e'"
    echo "  t - [required] ${DLP_AGENT_SERVER} type. Values: 'p' for primary or 's' for secondary"
    echo "  k - [required] PFX file path. If the file does not exist, it will be created"
    echo "  h - [required] PostgreSQL server name (only hostname)"
    echo "  p - [optional] PostgreSQL server communication port. Default value is '5432'"
    echo "  n - [required] Create a new database or use an existing one. Values: '1' to create a new database or '0' to use an existing one"
    echo "  d - [required] Database name"
    echo "  u - [required] Database username"
    echo "  z - [required] Database user password"
    echo "  s - [required] Install ${DLP_AGENT_SERVER} in stand-alone mode. Values: '1' to install the product in stand-alone mode or '0' to integrate it with ${DLP_SERVER_SHORTNAME}"
    echo "  x - [required] ${DLP_SERVER} address"
    echo "  a - [required] ${DLP_SERVER} authentication token"
    echo "  j - [optional] Platform pubkey in PEM format"
    echo "  w - [optional] Install ${DLP_AGENT} Distribution Service. Values: '1' or '0'"
    echo "  m - [optional] Migrate or remove device rule. Values: '1' or '0'"
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        echo "  i - [optional] Select installation type. Values: 'h' for Host or 'p' for Podman. Default value is 'h'"
    else
        echo "  i - [optional] Select installation type. Values: 'p' for Podman or 'd' for Docker. Default value is 'p'"
    fi
}

# Для IW_PARAMETERIZED_INSTALLATION
function parse_param() {
    optF=0
    optT=0
    optK=0
    optN=0
    optD=0
    optM=0
    optI=0
    while getopts ":f:l:t:k:h:p:n:m:d:u:z:s:x:a:j:w:i:" opt; do
        case $opt in

        f) ### Установка или обновление сервера, i/u
            optF=1;
            if [[ $IW_IS_CERTIFICATION_MODE -eq 1 ]]; then
                # сертифицированное исполнение нельзя обновить, только установка
                case $OPTARG in
                [Ii]*)
                    echo "Выбран режим установки install."
                    workMode="$IW_WORK_MODE_INSTALL"
                ;;
                * )
                    echo "Invalid argument for -f: $OPTARG. Use 'i'."
                    return 1
                ;;
                esac
            else
                # обычное исполнение
                case $OPTARG in
                [Ii]*)
                    echo "Выбран режим установки install."
                    workMode="$IW_WORK_MODE_INSTALL"
                ;;
                [Uu][Aa]*)
                    echo "Выбран режим обновления update ${DLP_WEB_UI} + ${DLP_AGENT_SERVER}."
                    workMode="$IW_WORK_MODE_UPDATE"
                    IW_UPDATE_FRONT=1
                    IW_UPDATE_BACK=1
                ;;
                [Uu][Ff]*)
                    echo "Выбран режим обновления update ${DLP_WEB_UI}."
                    workMode="$IW_WORK_MODE_UPDATE"
                    IW_UPDATE_FRONT=1
                ;;
                [Uu][Bb]*)
                    echo "Выбран режим обновления update ${DLP_AGENT_SERVER}."
                    workMode="$IW_WORK_MODE_UPDATE"
                    IW_UPDATE_BACK=1
                ;;
                * )
                    echo "Invalid argument for -f: $OPTARG. Use 'i' or 'u'."
                    return 1
                ;;
                esac
            fi
        ;;

        l) ### язык сервера, r/e
            case $OPTARG in
            [Rr]*)
                IW_CULTURE="$IW_CULTURE_RU"
                IW_CAS_LANG="$IW_CAS_LANG_RUS"
            ;;
            [Ee]*)
                IW_CULTURE="$IW_CULTURE_EN"
                IW_CAS_LANG="$IW_CAS_LANG_ENG"
            ;;
            * )
                echo "Invalid language!"
                return 1
            ;;
            esac
        ;;

        t) ### тип сервера (первичный или вторичный) p/s
            optT=1;
            case $OPTARG in
            [Pp]*)
                IW_IS_PRIMARY_SERVER=1
            ;;
            [Ss]*)
                IW_IS_PRIMARY_SERVER=0
            ;;
            * )
                echo "Invalid ${DLP_AGENT_SERVER} type!"
                return 1
            ;;
            esac
        ;;

        k) ### путь до ssl ключа, если его нет, будет создан
            optK=1
            if [ -f "$OPTARG" ]; then
                IW_SOURCE_PFX_FILE_PATH="$OPTARG"
                IW_VERIFY_PFX_FILE=1
            else
                local fileName
                if ! fileName=$(basename "$OPTARG"); then
                    echo "Invalid pfx file name: ${OPTARG}!"
                    return 1;
                fi

                IW_PFX_FILE_PATH="$IW_SERVER_DIRECTORY_PFX/$fileName"

                warning_msg "PFX file not exists $OPTARG. Create new $IW_PFX_FILE_PATH."
                IW_GENERATE_NEW_PFX_FILE=1
            fi
        ;;

        h) ### имя хоста СУБД Postgre
            IW_DB_SERVER=$OPTARG
        ;;

        p)
            IW_DB_SERVER_PORT=$OPTARG
        ;;

        n) ### создаем новую БД или ставим на существующую (1/0)
            optN=1
            case $OPTARG in
            [1]*)
                IW_IS_DB_UPGRADE=0
            ;;
            [0]*)
                IW_IS_DB_UPGRADE=1
            ;;
            * )
                echo "Invalid parameter value (create new or update DB)!"
                return 1
            ;;
            esac
        ;;

        d) ### имя БД
            optD=1
            IW_DB_NAME=$OPTARG
        ;;

        u) ### Имя пользователя СУБД
            IW_DB_USER=$OPTARG
        ;;

        z) ### Пароль пользователя СУБД
            IW_DB_PASSWORD=$OPTARG
        ;;

        s)  ### автономный режим (можно задать только через командную строку) 1/0
            IW_IS_STAND_ALONE_MODE=$OPTARG
            case $OPTARG in
            [1]*)
                IW_IS_STAND_ALONE_MODE=1
            ;;
            [0]*)
                IW_IS_STAND_ALONE_MODE=0
            ;;
            * )
                echo "Invalid parameter value (Is standalone mode)!"
                return 1
            ;;
            esac
        ;;

        x) ### адрес ТМ
            IW_TM_ADDRESS=$OPTARG
        ;;

        a) ### токен ТМ
            IW_TM_AUTH_TOKEN=$OPTARG
        ;;

        j) ### путь pubkey ключу платформы (нужен для проверки JWT токенов)
            IW_SRC_PUB_KEY_FILE_PATH=$OPTARG
            IW_COPY_PLATFORM_PUBKEY=1
        ;;

        w) ### Установить точку публикации
            IW_INSTALL_DISTRIB_SRV=$OPTARG
        ;;

        m) ### мигрировать/удалить правила (можно задать только через командную строку) 1/0
            optM=1
            case $OPTARG in
            [1]*)
                IW_MIGRATE_MODE=$IW_MIGRATE_RUN
            ;;
            [0]*)
                IW_MIGRATE_MODE=$IW_MIGRATE_REMOVE
            ;;
            * )
                echo "Invalid parameter value (Migrate mode)!"
                return 1
            ;;
            esac
        ;;

        i) ### выбрать тип установки host или docker 'h'/'d'
            optI=1
            case $OPTARG in
            [Hh]*)
                if [[ $IW_IS_CERTIFICATION_MODE -eq 1 ]]; then
                    # сертифицированное исполнение нельзя ставить на хост
                    echo "Unsupported ${DLP_AGENT_SERVER} install type!"
                    return 1
                fi
                IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
            ;;
            [Pp]*)
                IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_DOCKER_CMD="$PODMAN_CMD"
            ;;
            [Dd]*)
                if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
                    # НЕ сертифицированное исполнение нельзя ставить в docker, только host или podman
                    echo "Unsupported ${DLP_AGENT_SERVER} install type!"
                    return 1
                fi
                IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                IW_DOCKER_CMD="$DOCKER_CMD"
            ;;
            * )
                echo "Invalid ${DLP_AGENT_SERVER} install type!"
                return 1
            ;;
            esac
        ;;

        *) echo "Unknown parameter $opt!" ;;

        esac
    done

    if [[ $IW_INTERACTIVE_INSTALLATION -eq 0 ]]; then
        invalidParameters=0
        if [[ $optF -eq 0 ]]; then
            error_msg "Installation option has not been specified"
            invalidParameters=1
        fi
        if [ "$workMode" = "$IW_WORK_MODE_INSTALL" ]; then
            if [[ $optT -eq 0 ]]; then
                error_msg "${DLP_AGENT_SERVER} type (primary or secondary) not specified!"
                invalidParameters=1
            fi
            if [[ $optK -eq 0 ]]; then
                error_msg "PFX file not specified!"
                invalidParameters=1
            fi
            if [[ -z "${IW_DB_SERVER// }" ]]; then
                error_msg "PostgreSQL server name not specified!"
                invalidParameters=1
            fi
            if [[ $optN -eq 0 ]]; then
                error_msg "Create new database (1) or update (0) parameter not specified!"
                invalidParameters=1
            fi
            if [[ $optD -eq 0 ]]; then
                error_msg "Database name not specified!"
                invalidParameters=1
            fi
            if [[ -z "${IW_DB_USER// }" ]]; then
                error_msg "Database username not specified!"
                invalidParameters=1
            fi
            if [[ -z "${IW_DB_PASSWORD// }" ]]; then
                error_msg "Database user password not specified!"
                invalidParameters=1
            fi
            if [[ $IW_IS_STAND_ALONE_MODE -eq 0 ]]; then
                if [[ -z "${IW_TM_ADDRESS// }" ]]; then
                    error_msg "${DLP_SERVER} address not specified!"
                    invalidParameters=1
                fi
                if [[ -z "${IW_TM_AUTH_TOKEN// }" ]]; then
                    error_msg "${DLP_SERVER} auth token not specified!"
                    invalidParameters=1
                fi
            fi
            if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] && [[ $IW_IS_DB_UPGRADE -eq 1 ]]; then
                if [[ $optM -eq 0 ]]; then
                    error_msg "Migrate mode not specified!"
                    invalidParameters=1
                fi
            fi
            if [[ $optI -eq 0 ]]; then
                # значения по умолчанию для сертифицированного и обычного исполнения
                if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
                    # обычное исполнение
                    # "  i - [optional] Select installation type. Values: 'h' for Host or 'p' for Podman. Default value is 'h'"
                    IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                    IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                    IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                    IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
                else
                    # сертифицированное
                    # "  i - [optional] Select installation type. Values: 'p' for Podman or 'd' for Docker. Default value is 'p'"
                    IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                    IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                    IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                    IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
                    IW_DOCKER_CMD="$PODMAN_CMD"
                fi
            fi
        fi
        if [[ $invalidParameters -eq 1 ]]; then
            echo "Run $0 --help to view help message"
            return 1
        fi
    fi

    return 0
}

function select_command() {
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        # обычное исполнение
        local menu=(
            "Install"   # 0
            "Update"    # 1
            "Utilities" # 2
            "Exit"      # 3
        )
        select_from_menu "Select one of the options:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            workMode="$IW_WORK_MODE_INSTALL"
        elif [[ $selected_choice -eq 1 ]]; then
            workMode="$IW_WORK_MODE_UPDATE"
        elif [[ $selected_choice -eq 2 ]]; then
            workMode="$IW_WORK_MODE_UTIL"
        else # exit
            return 1
        fi
    else
        # сертифицированное
        local menu=(
            "Install"   # 0
            "Utilities" # 1
            "Exit"      # 2
        )
        select_from_menu "Select one of the options:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            workMode="$IW_WORK_MODE_INSTALL"
        elif [[ $selected_choice -eq 1 ]]; then
            workMode="$IW_WORK_MODE_UTIL"
        else # exit
            return 1
        fi
    fi
    return 0
}

function prompt_lang_culture() {
    local menu=( "Russian" "English" )
    local values=( "$IW_CULTURE_RU" "$IW_CULTURE_EN" )
    local casValues=( "$IW_CAS_LANG_RUS" "$IW_CAS_LANG_ENG" )

    select_from_menu "Select server language:" selected_choice "${menu[@]}"
    IW_CULTURE="${values[$selected_choice]}"
    IW_CAS_LANG="${casValues[$selected_choice]}"
}

function show_license_agreement() {
    local menu=(
        "View the license agreement"    # 0
        "Accept and continue"        # 1
        "Quit"                        # 2
    )
    while true; do
        select_from_menu "Do you accept the license agreement?" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            if [ "$IW_CULTURE" == "$IW_CULTURE_RU" ]; then
                less -E "$IW_APP/$IW_DMS_INST_DIR/license/$LICENSE_RU"
            else
                less -E "$IW_APP/$IW_DMS_INST_DIR/license/$LICENSE_EN"
            fi
        elif [[ $selected_choice -eq 1 ]]; then
            return 0
        elif [[ $selected_choice -eq 2 ]]; then
            return 1
        fi
    done
}

function prompt_installation_type() {
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        local menu=(
            "Host"               # 0
            "Container (podman)" # 1
        )
        select_from_menu "Select installation type:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq $IW_TYPE_HOST ]]; then
            IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
            IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
            IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
            IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_HOST"
        elif [[ $selected_choice -eq $IW_TYPE_DOCKER ]]; then
            IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
            IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
            IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
            IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
            IW_DOCKER_CMD="$PODMAN_CMD"
        fi
    else
        IW_SERVER_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
        IW_DB_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
        IW_DISTRIBUTION_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"
        IW_WEBAPI_DLL_INSTALLATION_TYPE="$IW_TYPE_DOCKER"

        local menu=( "Podman" "Docker" )
        local values=( "$PODMAN_CMD" "$DOCKER_CMD" )
        select_from_menu "Select a container system:" selected_choice "${menu[@]}"
        IW_DOCKER_CMD="${values[$selected_choice]}"
    fi
}

function select_install_components() {
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        local menu=(
            "${DLP_AGENT_SERVER_SERVICE}, Front End"   # 0
            "Front End only"                           # 1
            "${DLP_AGENT_SERVER_SERVICE} only"         # 2
            "Exit"                                     # 3
        )
        select_from_menu "Select installation components:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            IW_INSTALL_WEB_UI=1
            IW_INSTALL_IW_DM_SVR_SERVICE=1
        elif [[ $selected_choice -eq 1 ]]; then
            IW_INSTALL_WEB_UI=1
            IW_INSTALL_IW_DM_SVR_SERVICE=0
        elif [[ $selected_choice -eq 2 ]]; then
            IW_INSTALL_WEB_UI=0
            IW_INSTALL_IW_DM_SVR_SERVICE=1
        else # exit
            return 1
        fi
    else
        # в сертифицированном режиме нет варианта "все в одном", только покомпонентная установка
        local menu=(
            "Front End only"                           # 0
            "${DLP_AGENT_SERVER_SERVICE} only"         # 1
            "Exit"                                     # 2
        )
        select_from_menu "Select installation components:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            IW_INSTALL_WEB_UI=1
            IW_INSTALL_IW_DM_SVR_SERVICE=0
        elif [[ $selected_choice -eq 1 ]]; then
            IW_INSTALL_WEB_UI=0
            IW_INSTALL_IW_DM_SVR_SERVICE=1
        else # exit
            return 1
        fi
    fi
    return 0
}

function select_webui_installmode() {
    if [[ $IW_IS_CERTIFICATION_MODE -eq 0 ]]; then
        local menu=( "Central" "Office" )
        select_from_menu "Select Platform node mode:" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            # тут именно пустое значение
            IW_INSTALL_WEBUI_NODE_MODE=
        else
            IW_INSTALL_WEBUI_NODE_MODE="--nodemode=office --productmode=central"
        fi
    else
        # в сертифицированном исполнении ставимся только как для центральной ноды
        IW_INSTALL_WEBUI_NODE_MODE=
    fi
}

function prompt_server_role() {
    local menu=( "Primary" "Secondary" )
    select_from_menu "Select server role:" selected_choice "${menu[@]}"
    if [[ $selected_choice -eq 0 ]]; then
        IW_IS_PRIMARY_SERVER=1
    else
        IW_IS_PRIMARY_SERVER=0
    fi
}

function prompt_is_new_or_update_db() {
    if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]]; then
        local menu=( "Create a new database" "Upgrade an existing database" )
        select_from_menu "Would you like to create a new PostgreSQL database or upgrade an existing one?" selected_choice "${menu[@]}"
        if [[ $selected_choice -eq 0 ]]; then
            IW_IS_DB_UPGRADE=0
            return 0
        fi
    fi

    IW_IS_DB_UPGRADE=1
}

function prompt_db_credentials() {
    while true; do
        read -p "Enter PostgreSQL server name (hostname or IP): " IW_DB_SERVER
        if [[ ! -z "${IW_DB_SERVER// }" ]]; then
            break
        fi
    done

    read -p "Enter PostgreSQL server communication port [$IW_DB_SERVER_PORT]: " dbp
    IW_DB_SERVER_PORT=${dbp:-$IW_DB_SERVER_PORT}

    read -p "Enter database name [$IW_DB_NAME]: " dbn
    IW_DB_NAME=${dbn:-$IW_DB_NAME}

    read -p "Enter database username [$IW_DB_USER]: " dbu
    IW_DB_USER=${dbu:-$IW_DB_USER}

    read -p "Enter database user password: " -s IW_DB_PASSWORD
    echo
}

function prompt_is_need_install_iwdistrib() {
    if ask_YN_menu "Would you like to install ${DLP_AGENT_FULLNAME} Distribution Service?"
    then
        IW_INSTALL_DISTRIB_SRV=1
    else
        IW_INSTALL_DISTRIB_SRV=0
    fi
}

function prompt_pfx() {
    while true; do
        read -ep "Enter PFX file path [$IW_PFX_FILE_PATH]: " filePath
        local pfxFilePath=${filePath:-$IW_PFX_FILE_PATH}

        if [ -f "$pfxFilePath" ]; then
            IW_SOURCE_PFX_FILE_PATH="$pfxFilePath"
            IW_VERIFY_PFX_FILE=1
            return 0
        else
            if ask_YN_menu "PFX file does not exist. Would you like to create a new file?"; then
                IW_GENERATE_NEW_PFX_FILE=1
                return 0
            fi
        fi
    done
}

function prompt_tm_settings() {
    while true; do
        read -p "Enter ${DLP_SERVER} address: " IW_TM_ADDRESS
        if [[ ! -z "${IW_TM_ADDRESS// }" ]]; then
            break
        fi
    done

    while true; do
        read -p "Enter ${DLP_SERVER} auth token: " IW_TM_AUTH_TOKEN
        if [[ ! -z "${IW_TM_AUTH_TOKEN// }" ]]; then
            break
        fi
    done
}

function prompt_stand_alone_mode() {
    local menu=( "Integrate with ${DLP_SERVER_FULLNAME}" "Install in stand-alone mode" )
    select_from_menu "Select server role:" selected_choice "${menu[@]}"
    if [[ $selected_choice -eq 0 ]]; then
        IW_IS_STAND_ALONE_MODE=0
    else
        IW_IS_STAND_ALONE_MODE=1
    fi
}

function select_migration() {
    local menu=(
        "Using Device Control is required, migrate rules and white lists"    # 0
        "Using Device Control is not required, delete rules and white lists"    # 1
    )
    select_from_menu "Working with the rules controlling devices and white lists requires the installation of a new product Device Control. Beware that, declining Device Control installation will lead to deletion of your current rules and white lists!" selected_choice "${menu[@]}"
    if [[ $selected_choice -eq 0 ]]; then
        IW_MIGRATE_MODE=$IW_MIGRATE_RUN
    elif [[ $selected_choice -eq 1 ]]; then
        IW_MIGRATE_MODE=$IW_MIGRATE_REMOVE
    else # exit
        return 1
    fi
    return 0
}

function validate_params() {
    return 0
}

function interactive_install(){
    if ! select_install_components ; then exit 1 ; fi

    if [[ $IW_INSTALL_IW_DM_SVR_SERVICE -eq 1 ]] ; then
        if ! prompt_installation_type ; then exit 1 ; fi
    fi

    if ! validate_requirements ; then exit 1 ; fi

    if [[ $IW_INSTALL_WEB_UI -eq 1 ]]; then

        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_OS_SCRIPT"
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_PLATFORM_SCRIPT"
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_SYSTEM_CTL_SCRIPT"

        select_webui_installmode
        if ! extract_platfrorm_devicemonitor_setup "$IW_APP" ; then return 1 ; fi
        if ! run_platform_devicemonitor_setup "$IW_APP" "$IW_INSTALL_WEBUI_NODE_MODE" ; then return 1 ; fi

        if has_docker_installation ; then
            if ! validate_requirements_docker ; then return 1 ; fi
        fi
    fi

    if [[ $IW_INSTALL_IW_DM_SVR_SERVICE -eq 1 ]]; then
        prompt_lang_culture;
        if ! show_license_agreement ; then exit 1 ; fi
        prompt_server_role

        if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] ; then
            IW_INSTALL_WEBAPI_SERVICE=1
        else
            IW_INSTALL_WEBAPI_SERVICE=0
        fi

        prompt_is_new_or_update_db
        prompt_db_credentials
        prompt_is_need_install_iwdistrib

        if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] && [[ $IW_IS_DB_UPGRADE -eq 0 ]]; then
            prompt_pfx
        fi

        if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]]; then
            prompt_stand_alone_mode

            if [[ $IW_IS_STAND_ALONE_MODE -eq 0 ]]; then
                prompt_tm_settings
            fi
        fi

        if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] && [[ $IW_IS_DB_UPGRADE -eq 1 ]]; then
            select_migration
        fi

        if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] && [[ $IW_INSTALL_WEB_UI -eq 1 ]]; then
            get_IP_address
        fi

        validate_params

        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_INSTALL_SCRIPT"
    fi
}

function interactive_update() {
    if ask_YN_menu "Would you like to update ${DLP_WEB_UI}?"
    then
        IW_UPDATE_FRONT=1
    fi

    if ask_YN_menu "Would you like to update ${DLP_AGENT_SERVER_SERVICE}?"
    then
        IW_UPDATE_BACK=1
    fi

    if [[ $IW_UPDATE_FRONT -ne 1 ]] && [[ $IW_UPDATE_BACK -ne 1 ]] ; then
        # Обновлять нечего, ответили два раза "NO". Ошибкой не считаем.
        warning_msg "Nothing to update..."
        exit 0
    fi

    validate_params

    source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_UPDATE_SCRIPT"
}

function interactive_select_util() {
    local menu=(
        "Fix n.yaml file"                          # 0
        "Save Platform guard public key"           # 1
        "Show ${DLP_AGENT_SERVER_SERVICE} version" # 2
        "Export SSL key"                           # 3
        "Exit"                                     # 4
    )
    select_from_menu "Select utility:" IW_MODE_UTILS "${menu[@]}"

    if [[ $IW_MODE_UTILS -eq 0 ]]; then # Fix n.yaml
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_OS_SCRIPT"
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_PLATFORM_SCRIPT"

        get_IP_address
    fi

    source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_UTILS_SCRIPT"
}

#entry point

IW_APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
IW_INCLUDE_DIR="data/scripts/include"
IW_INC_VARIABLES="variables.sh"

source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_VARIABLES"
source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_COMMON_SCRIPT"
source "$IW_APP/$IW_INCLUDE_DIR/$IW_INCDE_SCR_SCRIPT"
source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_MESSAGE"
source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_DMS_COMMONS_SCRIPT"
source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_DOTNET_SCRIPT"

# reset terminal to ANSI mode.
echo -ne "\033[?1l"

# определяем есть ли возможность установки на хост, или только образы
# определяем до необходимости привелегий, т.к. usage тоже меняется
is_certification_mode "$IW_APP"

if [[ ( " $@ " == *" --help "*) ]] ; then usage && exit 1 ; fi

if [[ "$EUID" -ne 0 ]]; then echo "This script must be run as root!"  && exit 1 ; fi

if [ $# -gt 0 ] ; then
    IW_INTERACTIVE_INSTALLATION=0
    IW_PARAMETERIZED_INSTALLATION=1

    IW_INSTALL_DISTRIB_SRV=1

    if ! parse_param "$@" ; then exit 1 ; fi
else
    IW_INTERACTIVE_INSTALLATION=1
    IW_PARAMETERIZED_INSTALLATION=0
fi

if [[ $IW_INTERACTIVE_INSTALLATION -eq 1  ]]; then
    workMode="$IW_WORK_MODE_INSTALL"

    if ! select_command ; then exit 1 ; fi

    if [ "$workMode" = "$IW_WORK_MODE_INSTALL" ]; then
        interactive_install
    elif [ "$workMode" = "$IW_WORK_MODE_UPDATE" ]; then
        interactive_update
    elif [ "$workMode" = "$IW_WORK_MODE_UTIL" ]; then
        interactive_select_util
    fi
elif [[ $IW_PARAMETERIZED_INSTALLATION -eq 1  ]]; then
    IW_INSTALL_IW_DM_SVR_SERVICE=1

    if [[ $IW_IS_PRIMARY_SERVER -eq 1 ]] ; then
        IW_INSTALL_WEBAPI_SERVICE=1
    else
        IW_INSTALL_WEBAPI_SERVICE=0
    fi

    validate_params

    if [ "$workMode" = "$IW_WORK_MODE_INSTALL" ]; then
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_INSTALL_SCRIPT"
    elif [ "$workMode" = "$IW_WORK_MODE_UPDATE" ]; then
        source "$IW_APP/$IW_INCLUDE_DIR/$IW_INC_UPDATE_SCRIPT"
    fi
fi

