# (C) Copyright IBM Corp. 2021.

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.

FROM registry.access.redhat.com/ubi9/nodejs-16@sha256:d884fc989a81991c906244d77982784f7bc7c651782a2e2f200873de306f9679
USER root
RUN yum update -y && yum upgrade -y
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
