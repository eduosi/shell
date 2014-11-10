#!/bin/bash
#
# description: 该文件是基于 Git 为版本管理系统的前端自动化发布脚本，也实用与如 PHP、Python 等脚本语言系统。
#              该脚本主要是为了实现 javascript、css 文件的在发布时自动压缩。
#              该脚本是基于 YUI Compressor (http://yui.github.io/yuicompressor/) 来实现 javascript、css 文件的压缩。
#			   所以，运行该脚本，需要 Java 环境支持。
#              由于，在 javascript 代码书写不规范的情况下，容易导致压缩后的 javascript 不可用；所以，在生产环境发布之前，一定要经过严格的测试.
#
#              执行流程：(1)如果是第一次发布时，会从 Git 仓库 clone 一份代码到 PROJECT_DIR；或非第一次发布时，会切换到 PROJECT_DIR 执行 git pull 命令；
#                        (2)将当次更新的文件，记录到 UPDATE_LIST_FILE 文件中；
#                        (3)将 javascript 和 css 文件，压缩输出到 WEB_ROOT，非 javascript 和 css 文件或在压缩文件时出错，则 copy 到 WEB_ROOT；
#                        (4)从 WEB_ROOT 下删除已经从 Git 仓库中删除了的文件和目录；
#                        (5)发布完成。
#
#              PROJECT_DIR：项目源目录，WEB_ROOT：网站根目录。之所以，不直接在 WEB_ROOT 下压缩，是为了，避免压缩后的文件与 Git 仓库中更新下来的文件产生冲突。
#

set -e

PROJECT_NAME=""
PROJECT_DIR=""
WEB_ROOT=""
LOG_DIR="/var/log/"
YUICOMPRESSOR_JAR="/home/admin/script/release/lib/yuicompressor.jar"

CHARSET="UTF-8"
GIT_CHAESET="UTF-8"

GIT_PROTOCOL=${GIT_PROTOCOL-"ssh"}
GIT_HOST=${GIT_HOST-""}
GIT_PORT=${GIT_PORT-0}
GIT_USER=${GIT_USER-""}
BRANCH=${BRANCH-"master"}
# WEB_ROOT 所属用户组
GROUP=${GROUP-"nobody"}
# WEB_ROOT 所属用户
USER=${USER-"nobody"}

OPTIONS=""

note() {
	printf "$*\n" 1>&2;
}

warning() {
    printf "warning: $*\n" 1>&2;
}

error() {
    printf "error: $*\n" 1>&2;
    exit 1
}

usage() {
	me=`basename "$0"`

    echo "Usage: $me {release|rollback|h|help} [options]"
    echo "       -p, --project-name=项目名称		Git 项目名称"
    echo "       --project-dir=项目路径				项目项目源码存放路径"
    echo "       --web-root=WEB ROOT				项目关联网站根目录"
    echo "       --charset=项目字符集				项目文件字符集"
    echo "       --git-charset=Git 字符集			Git 终端显示字符集"
    echo "       --git-protocol=Git 协议			Git 请求协议"
    echo "       --git-host=Git 主机名称			Git 主机名称"
    echo "       --git-port=Git 主机端口			Git 主机端口"
    echo "       --git-user=Git 用户名				Git 用户名"
    echo "       -b, --branch=分支名称				当前使用分支"
    echo "       -g, --group=文件所属组				WEB ROOT 文件所属用户组"
    echo "       -u, --user=文件所说用户			WEB ROOT 文件所属用户"
    echo "       --log-dir=日志目录					log direetory"

    exit 1
}

check() {
	if [ -z "$PROJECT_NAME" ]; then
		error "project name could not be empty"
	fi

	if [ -z "$PROJECT_DIR" ]; then
		error "project direetory could not be empty"
	fi

	if [ -z "$WEB_ROOT" ]; then
		error "project web root could not be empty"
	fi
}

update_files_init() {
    local arg=$1
    local path="$PROJECT_DIR/$arg"

    if [ -d "$path" ]; then
        local files=`ls "$path"`

        for file in $files
        do
            local _path="$path/$file"
            local temp="$file"

            if [ ! "$arg" == "" ]; then
                temp="$arg/$temp"
            fi

            if [ -d "$_path" ]; then
                update_files_init "$temp"
            else
                echo "$temp" >> $UPDATE_LIST_FILE
            fi
        done
    elif  [ -f "$path" ]; then
        echo "$arg" >> $UPDATE_LIST_FILE
    else
        warning "$path is not exists";
    fi

    return 0
}

condense() {
    local type=$1
    local source_file=$2
    local target_file=$3
    local MSG="Compression "

    if [ "$type" == "js" ]; then
        MSG=$MSG"javascript"
    else
        MSG=$MSG"css"
    fi
    MSG=$MSG" file $source_file to $target_file"

    note $MSG" success"
    java -jar ${YUICOMPRESSOR_JAR} --type ${type} --charset ${CHARSET} "$source_file" -o "$target_file" || { warning "$MSG failure"; note "so copy $source_file to $target_file"; \cp $source_file $target_file; }

    chown ${USER}:${GROUP} "$target_file"
}

operate() {
	local file=$1

	if [ ! -z "$file" ]; then
		local source_file="$PROJECT_DIR/$file"
		local target_file="$WEB_ROOT/$file"
		local target_dir=`dirname "$target_file"`

		if [ -f "$source_file" ]; then
			mkdir -p "$target_dir" || { warning "create target directory $target_dir failure"; }

			if [[ "$source_file" =~ .js$ ]]; then
				condense "js" "$source_file" "$target_file"
			elif [[ "$source_file" =~ .css$ ]]; then
				condense "css" "$source_file" "$target_file"
			else
				note $"Copy file $source_file to $target_file"
				cp "$source_file" "$target_file"
			fi

			chown ${USER}:${GROUP} "$target_file"
		fi
	fi
}

delete_file() {
	local file=$1

	if [ ! -z "$file" ]; then
		local source_dir=`dirname "$PROJECT_DIR/$file"`
		local target_file="$WEB_ROOT/$file"
		local target_dir=`dirname "$target_file"`

		if [ ! -d "$source_dir" ]; then
			note "clear directory $target_dir"
			rm -fR "$target_dir"
		else
			note "Delete file $target_file"
			rm -f "$target_file"
		fi
	fi
}

release() {
	note "Release project $PROJECT_NAME";

	check

	local git_dir=$PROJECT_DIR"/.git"
	if [ ! -d $git_dir ]; then
		if [ -z "$GIT_PROTOCOL" ]; then
			error "project git protocol could not be empty"
		fi

		if [ -z "$GIT_HOST" ]; then
			error "project git host could not be empty"
		fi

		if [ -z "$GIT_PORT" ]; then
			error "project git port could not be empty"
		fi

		if [ -z "$GIT_USER" ]; then
			error "project git username could not be empty"
		fi

		note "initialize project $PROJECT_NAME with source direetory $PROJECT_DIR and WEB ROOT $WEB_ROOT";
    fi

    mkdir -p $LOG_DIR || { error "create log directory $LOG_DIR failure"; }

    if [ -f $UPDATE_LIST_FILE ]; then
        rm $UPDATE_LIST_FILE || { error "Remove $UPDATE_LIST_FILE failure"; }
    fi

    if [ -d $PROJECT_DIR ]
    then
        cd $PROJECT_DIR
        git pull origin ${BRANCH} > $RELEASE_LOG || { error "git pull code failure"; }

        local temp=`grep 'Already up-to-date' $RELEASE_LOG`
        if [ "$temp" == "" ]; then
            note "List update files";
        else
            warning "Already up-to-date";
            exit 1;
        fi

		note "checkout $BRANCH branch"
		git checkout ${BRANCH}
		sleep 1
		git diff-tree -r --name-status --no-commit-id ORIG_HEAD HEAD > $UPDATE_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F '^A' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $UPDATE_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F '^M' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $UPDATE_LIST_FILE

		while read i;
        do
            temp=`echo $i|awk -F '^D' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
			delete_file "$temp";
        done < $UPDATE_LIST_FILE
    else
        cd `dirname "$PROJECT_DIR"`

		local project_git_url="$GIT_PROTOCOL://$GIT_USER@$GIT_HOST:$GIT_PORT/$PROJECT_NAME"
        git clone ${project_git_url} > $RELEASE_LOG || { error "git clone $PROJECT_NAME form $GIT_URL error"; }

		cd $PROJECT_DIR

		note "Checkout $BRANCH branch"
		git checkout ${BRANCH}
		sleep 1

        note "List update files"

        update_files_init "" || { error "update files init failure"; }

		local files=`cat $UPDATE_LIST_FILE`

		for file in $files
		do
			operate "$file"
		done

		chown ${USER}:${GROUP} "$WEB_ROOT"
    fi
}

rollback() {
	note "Rollback project $PROJECT_NAME";

	check

    if [ "$OPTIONS" == "" ]; then
        error "rollback options could not be empty";
    else
        cd $PROJECT_DIR

		note "Checkout $BRANCH branch"
		git checkout ${BRANCH}

		sleep 1

        git reset --hard $OPTIONS
        git diff-tree HEAD HEAD^ -r --name-status > $ROLLBACK_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F '^A' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            delete_file "$temp";
        done < $ROLLBACK_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F '^M' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $ROLLBACK_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F '^D' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $ROLLBACK_LIST_FILE
    fi
}

ACTION=$1
shift

args_count=$#
args_count=`expr $args_count - 1`
i=0

while test $i -le $args_count ;
do
	case "$1" in
		-p=*)
			PROJECT_NAME=${1##-p=}
			shift
			i=`expr $i + 1`
			;;
		--project-name=*)
			PROJECT_NAME=${1##--project-name=}
			shift
			i=`expr $i + 1`
			;;
		--project-dir=*)
			PROJECT_DIR=${1##--project-dir=}
			shift
			i=`expr $i + 1`
			;;
		--web-root=*)
			WEB_ROOT=${1##--web-root=}
			shift
			i=`expr $i + 1`
			;;
		--charset=*)
			CHARSET=${1##--charset=}
			shift
			i=`expr $i + 1`
			;;
		--git-charset=*)
			GIT_CHAESET=${1##--git-charset=}
			shift
			i=`expr $i + 1`
			;;
		--git-protocol=*)
			GIT_PROTOCOL=${1##--git-protocol=}
			shift
			i=`expr $i + 1`
			;;
		--git-host=*)
			GIT_HOST=${1##--git-host=}
			shift
			i=`expr $i + 1`
			;;
		--git-port=*)
			GIT_PORT=${1##--git-port=}
			shift
			i=`expr $i + 1`
			;;
		--git-user=*)
			GIT_USER=${1##--git-user=}
			shift
			i=`expr $i + 1`
			;;
		-b=*)
			BRANCH=${1##-b=}
			shift
			i=`expr $i + 1`
			;;
		--branch=*)
			BRANCH=${1##--branch=}
			shift
			i=`expr $i + 1`
			;;
		-g=*)
			GROUP=${1##-g=}
			shift
			i=`expr $i + 1`
			;;
		--group=*)
			GROUP=${1##--group=}
			shift
			i=`expr $i + 1`
			;;
		-u=*)
			USER=${1##-u=}
			shift
			i=`expr $i + 1`
			;;
		--user=*)
			USER=${1##--user=}
			shift
			i=`expr $i + 1`
			;;
		--log-dir=*)
			LOG_DIR=${1##--log-dir=}
			shift
			i=`expr $i + 1`
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			case "$ACTION" in
				rollback)
					OPTIONS=$OPTIONS" "$1
					shift
					i=`expr $i + 1`
					;;
				*)
					usage
					exit 0
					;;
			esac
	esac
done

# 设置编码和文件名允许中文等字符  
git config --global core.quotepath false         # 设置文件名允许中文等字符
git config --global i18n.logoutputencoding ${GIT_CHAESET} # 设置 git log 输出时编码
export LESSCHARSET=${GIT_CHAESET}

RELEASE_LOG=$LOG_DIR"/release.log"
UPDATE_LIST_FILE=$LOG_DIR"/update_list.txt"
ROLLBACK_LIST_FILE=$LOG_DIR"/rollback_list.txt"

case "$ACTION" in
    release|rollback)
        $ACTION
        ;;
    *)
        echo "Usage: $0 {release|rollback}"
        ;;
esac

exit 0