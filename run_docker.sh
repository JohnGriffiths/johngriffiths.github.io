#sudo docker build -t pelican .
docker pull johngriffiths/pelican
docker run -t --name=pelican-run -v $(pwd):/site johngriffiths/pelican
docker rm pelican-run
