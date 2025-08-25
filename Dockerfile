FROM golang:1.23 as build

# ENV GOPROXY=https://goproxy.cn,direct
ENV GO111MODULE=on

# 安装 Node.js 和 Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update -y && apt-get install -y yarn
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
RUN GIT_COMMIT=$(git rev-parse HEAD || echo "unknown") && \
    GIT_COMMIT_DATE=$(git log --date=iso8601-strict -1 --pretty=%ct || echo "0") && \
    GIT_VERSION=$(git describe --tags --abbrev=0 || echo "v0.0.0-unknown") && \
    GIT_TREE_STATE=$(test -n "$(git status --porcelain)" && echo "dirty" || echo "clean") && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -extldflags '-static' -X main.Commit=$GIT_COMMIT -X main.CommitDate=$GIT_COMMIT_DATE -X main.Version=$GIT_VERSION -X main.TreeState=$GIT_TREE_STATE" -installsuffix cgo -o app ./main.go

FROM alpine as prod
# 添加 ca-certificates 和 tzdata
RUN apk --no-cache add ca-certificates tzdata

# 创建 non-root 用户
RUN adduser -D -g '' appuser

# 创建目录并设置权限
RUN mkdir -p /app/config /home && chown -R appuser:appuser /app /home

WORKDIR /home
COPY --from=build --chown=appuser:appuser /go/release/app /home/app

# 可选：复制 wk.yaml
COPY --from=build --chown=appuser:appuser /go/release/config/wk.yaml /app/config/wk.yaml

# 调试：打印所有环境变量（在容器启动前）
CMD ["/bin/sh", "-c", "echo 'Debug: Environment Variables:' && env && exec /home/app --ignoreMissingConfig=true"]

# 切换到 non-root 用户
USER appuser

# ENTRYPOINT（保持纯 env 模式，但用 CMD 包裹调试）
