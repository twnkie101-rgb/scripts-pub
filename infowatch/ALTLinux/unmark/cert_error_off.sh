#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт нужно запускать от имени root!"
    exit 1
fi

su - postgres -s /bin/bash -c "psql -d iwdm -c \"UPDATE public.\\\"Settings\\\" SET \\\"Value\\\" = 'True' WHERE \\\"Name\\\" LIKE 'IGNORE_SSLERR%';\""
