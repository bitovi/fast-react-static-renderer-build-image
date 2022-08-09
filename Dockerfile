FROM node:16

WORKDIR /opt/frsr-build
COPY . .

RUN apt-get update

RUN apt-get install -y \
  bash \
  python3 \
  python3-pip \
  jq

RUN pip3 install --upgrade pip
RUN pip3 --no-cache-dir install --upgrade awscli
RUN apt-get clean

# puppeteer attempt 1
# https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#running-puppeteer-in-docker
# quickly got into whack-a-mole with user permissions and such. 

# puppeteer attempt 2
# https://www.cloudsavvyit.com/13461/how-to-run-puppeteer-and-headless-chrome-in-a-docker-container/
RUN apt-get install -y \
    fonts-liberation \
    gconf-service \
    libappindicator1 \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libfontconfig1 \
    libgbm-dev \
    libgdk-pixbuf2.0-0 \
    libgtk-3-0 \
    libicu-dev \
    libjpeg-dev \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpng-dev \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    xdg-utils


CMD ["/bin/bash"]
ENTRYPOINT [ "/opt/frsr-build/scripts/build/build.sh" ]
