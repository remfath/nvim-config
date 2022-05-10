cd local
find . -type d -name ".git" | xargs rm -rf
find . -type d -name ".github" | xargs rm -rf

cd ../config
find . -type d -name ".git" | xargs rm -rf
find . -type d -name ".github" | xargs rm -rf

cd ../cache
find . -type d -name ".git" | xargs rm -rf
find . -type d -name ".github" | xargs rm -rf
