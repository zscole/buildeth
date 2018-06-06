#!/bin/bash

rm -rf /home/appo/node*

function usage {
		cat <<EOM
	 Usage: create_block -g <gaslimit> -c <chainId> -n <networkid> -N <Number of nodes>
	 Example: create_block -c 17835211 -n 178354 -N 12
EOM
	exit 1
}

c=17835
n=17835
gas=
while getopts "g:c:n:N:h" optKey; do
	case $optKey in
		c)
			c=$OPTARG
			;;
		n)
			n=$OPTARG
			;;
		N)
			N=$OPTARG
			;;
		g)
			gas=$OPTARG
			;;
		h|*)
			usage
			;;
	esac
done

rm /tmp/static-nodes.json

i=1
while [ "$i" -le "$N" ]; do

	# Create the node directory
	mkdir /home/appo/node$i

	# Create a new account/wallet
	for addline in {1..35}; do
	 	echo second >> /home/appo/node$i/passwd.file
	done
	geth --datadir /home/appo/node$i/ --password /home/appo/node$i/passwd.file account new | awk '{print $2}' | sed -E 's/\{|\}//g' > /home/appo/node$i/wallet
	(( i++ ))
done
count=$N

# gathering all wallets into one file
for wall in `find /home/appo/node*/ -type f -name wallet`; do
  	wallet=`cat $wall`
  	echo -e "$wallet" >> /tmp/all_wallet
done

#Adding money to all wallets
alloc=`cat /tmp/all_wallet | sed -e 's/^/"/' | sed -e 's/$/": \{\"balance\"\: \"100000000000000000000\"\},/' | sed '$ s/.$//'`

unlock=`cat /tmp/all_wallet | sed -e ':a;N;$!ba;s/\n/,/g'`

# Create the CustomGenesis.json file

cat <<EOF > /tmp/CustomGenesis.json
{
	"config": {
		"chainId": $c,
		"homesteadBlock": 0,
		"eip155Block": 0,
		"eip158Block": 0
	},
	"difficulty": "0x0400",
	"gasLimit": "0x2100000",
	"alloc": {
$alloc
 }
}
EOF

i=1
while [ "$i" -le "$N" ]; do
	echo "---------------------  CREATING block directory for NODE-$i  ---------------------"

	# set the ip address for the enode
	nodeIP=10.$i.100.100

	# Load the CustomeGenesis file
	geth --datadir /home/appo/node$i init /tmp/CustomGenesis.json

	# Get the enode from console and drop out of console
	geth --rpc --datadir /home/appo/node$i/ --networkid $n console >& /tmp/node$i.output

	# Inject the IP Adress into the enode string
	enode=`cat /tmp/node$i.output | grep enode | awk '{print $5}'| sed "s/\[::\]/$nodeIP/g"`

	# Write the enode info to the node directory
	echo $enode >> /home/appo/node$i/enode

	# Create the static nodes file

	if [ -f "/tmp/static-nodes.json" ]; then
		## ------------------------------------#
		cat >> /tmp/static-nodes.json <<EOL
		"$enode",
EOL
		## ------------------------------------#
	else
		## ------------------------------------#
		echo "[" > /tmp/static-nodes.json
		cat >> /tmp/static-nodes.json <<EOL
		"$enode",
EOL

	fi

(( i++ ))
done

echo "---------------------  Setting Up Node Directories  ---------------------"
#  Copy all UTC keystore files to every Node directory
one=1
while [ "$one" -le "$N" ]; do
   	for LINE in `find /home/appo/node*/ -type f -name UTC* | grep -v node$one`
   	do
	 	cp $LINE /home/appo/node$one/keystore
	done
	(( one++ ))
done

# Send the closing bracket "]" to static nodes file
sed -i '$s/\",/\"/g' /tmp/static-nodes.json
echo "]" >> /tmp/static-nodes.json

one=1
while [ "$one" -le "$count" ]; do
# Copy static nodes to each node directory
   	cp /tmp/static-nodes.json /home/appo/node$one
   	(( one++ ))
done
killall node 
pm2 kill
e=1
# Copy datadir to each peer node
while [ $e -le $N ]
do
		function expect_password {
		expect -c "\
		 set timeout 90
		 set env(TERM)
		 spawn $1
		 expect \"*password:\"
		 send \"w@ntest\r\"
		expect eof
		"
		}
  	# Updating Log
  	echo "-----------------------------  Starting NODE-$e  -----------------------------" >> /tmp/$(date "+%y.%m.%d").log

  	# Copy net inteligence api to node directory
  	cp -r /home/appo/eth-net-intelligence-api/ /home/appo/node$e/eth-net-intelligence-api/ >> /tmp/$(date "+%y.%m.%d").log
  	sed -i "s/\"INSTANCE_NAME\".*/\"INSTANCE_NAME\"\t\:\ \"node$e\",/g" /home/appo/node$e/eth-net-intelligence-api/app.json
  	cd /home/appo/node$e/
  	tar -cf eth-net-intelligence-api.tar ./ >> /tmp/$(date "+%y.%m.%d").log
  	#  rm -rf /home/appo/node$e/eth-net-intelligence-api/

 	expect_password "ssh -t -o StrictHostKeyChecking=no node$e rm -Rf /home/appo/node$one"


  	#Kill all running instances of console it it is running
  	expect_password "ssh -t -o StrictHostKeyChecking=no node$e tmux kill-server"

	# Copy the Node directories to the respective nodes
	expect_password "scp -p -o StrictHostKeyChecking=no -r /home/appo/node$e appo@node$e:/home/appo"

	# Starting tmux on every node
	expect_password "ssh -t -o StrictHostKeyChecking=no node$e tmux new -s whiteblock -d"

	# Starting console in tmux on every node
	expect_password "ssh -t -o StrictHostKeyChecking=no node$e tmux send-keys -t whiteblock 'geth\ --datadir\ /home/appo/node$e\ --nodiscover\ --maxpeers\ 50\ --targetgaslimit\ $gas\ --networkid\ $n\ --rpc\ --unlock \\\"$unlock\\\" --password /home/appo/node$e/passwd.file --etherbase `cat /home/appo/node$e/wallet` console' C-m"

	#Start the net inteligence API on all nodes
	expect_password "ssh -t -o StrictHostKeyChecking=no node$e cd /home/appo/node$e && tar -xf eth-net-intelligence-api.tar && cd /home/appo/node$e/eth-net-intelligence-api && pm2 start app.json && rm /home/appo/node$e/eth-net-intelligence-api.tar" >> /tmp/$(date "+%y.%m.%d").log

	(( e++ ))
done

tmux new -s netstats -d
tmux send-keys -t netstats 'cd /home/appo/eth-netstats' C-m
tmux send-keys -t netstats 'WS_SECRET=second npm start' C-m

echo "To view geth console type:                         tmux attach-session -t whiteblock"
echo "To view Eth Net Stat type:                         tmux attach-session -t netstats"


rm -f /tmp/all_wallet
