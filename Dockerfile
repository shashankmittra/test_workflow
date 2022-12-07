# (C) Copyright IBM Corp. 2021.

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.

FROM registry.access.redhat.com/ubi8/nodejs-16@sha256:4b3aa4f8f4b98c2a03342115283d10a50be62d662cd9c2153fddf1739e25766a
USER root
RUN yum update -y && yum upgrade -y

# to mitigate CVE-2022-3517
RUN yum remove -y nodejs-nodemon

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
