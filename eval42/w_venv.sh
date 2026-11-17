python -m venv /shared/w/venv > /tmp/v.log 2>&1; echo "WORKLOAD venv exit=$?"
tail -3 /tmp/v.log
/shared/w/venv/bin/python -c 'print("VENV_PYTHON_OK")' 2>&1 | tail -1
echo "FILES $(find /shared/w/venv | wc -l) SYMLINKS $(find /shared/w/venv -type l | wc -l)"
