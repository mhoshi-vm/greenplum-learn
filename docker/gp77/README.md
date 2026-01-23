```
docker build --build-arg PIVNET_API_TOKEN=[broadcom download token] -t gp7-analytics .
```

On Apple Silcon

```
docker buildx build --platform=linux/amd64 --build-arg PIVNET_API_TOKEN=[broadcom download token]  -t gp7-analytics .     
```