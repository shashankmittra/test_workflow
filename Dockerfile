# (C) Copyright IBM Corp. 2021.

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.

FROM registry.access.redhat.com/ubi8/nodejs-18@sha256:a6d1a446d42e17f503bf24a4e3b598f382d07f2242b22246e1c3114662f48245
USER root
RUN yum update -y && yum upgrade -y

# to mitigate CVE-2022-3517 CVE-2022-43548
RUN yum remove -y nodejs-nodemon nodejs-docs nodejs-full-i18n

# some change from cra for which this is workaround from David Lopez, see: https://ibm-cloudplatform.slack.com/archives/C14UWH9C4/p1666718978490169?thread_ts=1666226706.155919&cid=C14UWH9C4
RUN rm -rf /usr/lib/python3.6/site-packages/pip-9.0.3.dist-info

RUN npm -v
ENV PORT 8080
WORKDIR /usr/src/app
RUN chown -R 1001:0 /usr/src/app
COPY package*.json ./
RUN npm install
COPY . .
USER 1001
EXPOSE 8080
CMD [ "npm", "start" ]
