# HPE Live: sbin-Verzeichnisse auch für normale Benutzer (wie bei Ubuntu),
# damit Hardwaretest & Co. nvme, zpool, smartctl, lvm, mdadm usw. finden.
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"; export PATH ;;
esac

# Standardbrowser (Python webbrowser, xdg-open): surf über den firefox-Wrapper
BROWSER=firefox; export BROWSER
