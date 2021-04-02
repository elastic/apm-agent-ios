for ip in $(dig @8.8.8.8 github.com +short); do ssh-keyscan github.com,$ip; ssh-keyscan $ip; done 2>/dev/null >> ~/.ssh/known_hosts         
xcodebuild -scheme iOSAgent -sdk iphoneos14.4
