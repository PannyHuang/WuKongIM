FROM golang:1.23 as build

# ENV GOPROXY=https://goproxy.cn,direct
ENV GO111MODULE=on

# 安装 Node.js 和 Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg |  apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" |  tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update -y  && apt-get install -y yarn
RUN apt-get install -y nodejs
RUN yarn config set registry https://registry.npm.taobao.org -g

# 编译前端demo
WORKDIR /go/release/demo
ADD demo .

#------ 编译chatdemo ------
# WORKDIR /go/release/demo/chatdemo
# RUN yarn install && yarn build

# 编译前端 monitor
WORKDIR /go/release/web
ADD web .
RUN yarn install && yarn build

# 编译后端

WORKDIR /go/cache

ADD go.mod .
ADD go.sum .
RUN go mod download

WORKDIR /go/release
ADD . .

RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags='-w -extldflags "-static"' -o app main.go

RUN GIT_COMMIT=$(git rev-parse HEAD || echo "unknown") && \
    GIT_COMMIT_DATE=$(git log --date=iso8601-strict -1 --pretty=%ct || echo "0") && \
    GIT_VERSION=$(git describe --tags --abbrev=0 || echo "v0.0.0-unknown") && \
    GIT_TREE_STATE=$(test -n "$(git status --porcelain)" && echo "dirty" || echo "clean") && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -extldflags '-static' -X main.Commit=$GIT_COMMIT -X main.CommitDate=$GIT_COMMIT_DATE -X main.Version=$GIT_VERSION -X main.TreeState=$GIT_TREE_STATE" -installsuffix cgo -o app ./main.go


FROM alpine as prod
# Import the user and group files from the builder.
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# 创建配置目录（non-root 路径）
RUN mkdir -p /app/config && chmod 755 /app/config  # 权限：目录可读

WORKDIR /home
COPY --from=build /go/release/app /home

# 复制 wk.yaml 到新路径，并设置权限
COPY --from=build /go/release/config/wk.yaml /app/config/wk.yaml
RUN chmod 644 /app/config/wk.yaml  # 确保文件可读（rw-r--r--）

# 调试：输出 prod 阶段文件结构
RUN ls -la /app  # 应该显示 config/
RUN ls -la /app/config  # 应该显示 wk.yaml
RUN ls -la /app/config/wk.yaml || echo "wk.yaml not copied to prod stage!"
RUN cat /app/config/wk.yaml || echo "Failed to cat wk.yaml in prod stage!"  # 输出内容确认

# ENTRYPOINT：指定配置文件路径
ENTRYPOINT ["/home/app", "--config=/app/config/wk.yaml", "--ignoreMissingConfig=true"]
