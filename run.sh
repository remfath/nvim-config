cd local
find . -type d -name ".git" | xargs rm -rf

cd ../config
find . -type d -name ".git" | xargs rm -rf

cd ../cache
find . -type d -name ".git" | xargs rm -rf
