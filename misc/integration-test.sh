#!/bin/bash -e
SLP=1

# nobody else will create this.
# hopefuly.
vmname=SPTEST.fadCarlarr

function waitforimg() {
	do_waitfor oneimage $1 $2
}

function waitforvm() {
	do_waitfor onevm $1 $2
}

function do_waitfor() {
	local state
	local timeout
	local cmd
	cmd="$1"
	state="$2"
	if [ -z "$3" ]; then
		timeout=60
	else
		timeout="$3"
	fi

	local sec

	sec=0

	local st

	while /bin/true; do

		st=`$cmd list --list STAT,NAME --csv | grep "$vmname"'$'|cut -d , -f 1`
		if [ "$st" = "$state" ]; then
			return 0
		fi

		sleep $SLP
		let sec=$sec+$SLP
		if [ "$sec" -gt "$timeout" ]; then
			return 1
		fi
	done

}

function die() {
	echo "Dying: $1"
	exit 5
}


if ! which storpool >/dev/null 2>/dev/null; then
	echo storpool cli not installed
	exit 2
fi

if ! which onevm >/dev/null 2>/dev/null; then
	echo ONE cli not installed
	exit 2
fi

if ! [ -d /var/lib/one/remotes/datastore/storpool ] || ! [ -d /var/lib/one/remotes/tm/storpool ] ; then
	echo storpool ONE addon not installed
	exit 2
fi

if ! onedatastore list --list DS --csv |grep -q storpool; then
	echo Storpool datastore does not exist.
	exit 2
fi

if [ -z "$4" ]; then
	echo Usage: $0 templateid host1 host2
	echo 
	onetemplate list
	onehost list
	exit 2
fi

ds=`onedatastore list --list ID,TM,TYPE --csv  | grep 'storpool,img$' | head -n1 | cut -d , -f 1`

tmpl="$1"
h1="$2"
h2="$3"

if onevm list --list NAME --csv |grep -q '^'$vmname'$'; then
	echo vm $vmname exists, removing.
	onevm terminate --hard "$vmname"
fi

echo -n "Creating VM $vmname..."
onetemplate instantiate $tmpl --name $vmname
waitforvm runn 120 || die "vm creation failed"
vmid=`onevm list --list ID,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
chost=`onevm list --list HOST,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
echo "done, id $vmid host $chost."

if [ "$chost" = "$h1" ]; then
	htm=$h2
else
	htm=$h1
fi

first=$chost
second=$htm

echo -n "Migrating live to $htm..."
onevm migrate --live $vmid $htm
waitforvm runn || die "migration broke"
nhost=`onevm list --list HOST,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
if ! [ "$nhost" = "$htm" ]; then
	die "did not move to $htm, is on $nhost"
fi
echo "done, now on $nhost."

htm=$chost

echo -n "Migrating live back to $htm..."
onevm migrate --live $vmid $htm
waitforvm runn || die "migration broke"
nhost=`onevm list --list HOST,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
if ! [ "$nhost" = "$htm" ]; then
	die "did not move to $htm, is on $nhost"
fi
echo "done, now on $nhost."

echo -n "Powering off..."
onevm poweroff --hard $vmid
waitforvm poff || die "cannot power off"
echo "done."

echo -n "Moving to $second..."
onevm migrate $vmid $second
waitforvm poff || die "migration broke"
nhost=`onevm list --list HOST,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
if ! [ "$nhost" = "$second" ]; then
	die "did not move to $second, is on $nhost"
fi
echo "done, now on $nhost."

echo -n "Powering up..."
onevm resume $vmid
waitforvm runn || die "cannot power up"
echo "done."

echo -n "Powering off again..."
onevm poweroff --hard $vmid
waitforvm poff || die "cannot power off"
echo "done."

echo -n "Moving back to $first..."
onevm migrate $vmid $first
waitforvm poff || die "migration broke"
nhost=`onevm list --list HOST,NAME --csv |grep "$vmname"'$' |cut -d , -f 1`
if ! [ "$nhost" = "$first" ]; then
	die "did not move to $first, is on $nhost"
fi
echo " done, now on $nhost."

echo -n "Powering up..."
onevm resume $vmid
waitforvm runn || die "cannot power up"
echo "done."


iid=`oneimage list --list ID,NAME --csv | grep "$vmname"'$' |cut -d , -f 1`

if ! [ -z "$iid" ]; then
	echo -n "Image $vmname exists as id $iid, removing..."
	oneimage delete $iid
	waitforimg ""
	echo "done."
fi

echo -n "Creating test image..."
oneimage create --name $vmname -d $ds --size 10000 --type datablock --driver raw --prefix vd >/dev/null

waitforimg rdy || die "image creation failed"

iid=`oneimage list --list ID,NAME --csv | grep "$vmname"'$' |cut -d , -f 1`

echo "done, id $iid."


echo -n "Attaching image $iid to vm $vmid..."
onevm disk-attach $vmid --image $iid
waitforvm runn || die "attachment hung"
# check attach

ndisk=`onevm show $vmid --xml | xmllint  --nocdata --xpath 'count(//VM/TEMPLATE/DISK)' -`
for i in `seq 1 $ndisk`; do
	ciid=`onevm show $vmid --xml | xmllint  --nocdata --xpath '//VM/TEMPLATE/DISK['$i']/IMAGE_ID/text()' -`
	if [[ "$iid" = "$ciid" ]]; then
		did=$i
		break
	fi
done
if [[ -z "$did" ]]; then
	die "Attachment failed"
fi

echo done.
oneimage list
onevm list
echo -n "Detaching disk $did from vm $vmid..."
for j in `seq 1 10`; do
	onevm disk-detach $vmid $did
	# check detach
	waitforvm runn || die "detachment hung"

	did=''
	ndisk=`onevm show $vmid --xml | xmllint  --nocdata --xpath 'count(//VM/TEMPLATE/DISK)' -`
	for i in `seq 1 $ndisk`; do
		ciid=`onevm show $vmid --xml | xmllint  --nocdata --xpath '//VM/TEMPLATE/DISK['$i']/IMAGE_ID/text()' -`
		if [[ "$iid" = "$ciid" ]]; then
			did=$i
			break
		fi
	done
	if [[ -z "$did" ]]; then
		break
	fi
	echo -n "$j..."
	sleep 5
done
echo "done."

if ! [[ -z "$did" ]]; then
	die "Detachment failed"
fi


echo -n "Removing image $iid..."
oneimage delete $iid
waitforimg ""  || die "removal failed."
echo "done."

echo -n "Removing $vmname..."
onevm terminate --hard "$vmname"
waitforvm ""
echo "done."

echo "Validaion passed."
