attach docker rails

```bash
# terminal 1
docker build -t rails-container .
docker run --name rails --rm -d -p 12345:12345 -p 3000:3000 rails-container
docker exec rails rails db:migrate

# terminal 2
nvim app/controllers/samples_controller.rb
# set breakpoint at index
# :DapContinue
# select 'Ruby Debugger: Rails server (docker)'

# terminal 3
curl http://localhost:3000/samples

docker stop rails
docker rm rails
```
