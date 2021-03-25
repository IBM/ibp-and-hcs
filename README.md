## ibp-and-hcs

At the time of writing, the guide works for IBM Blockchain Platform (hereafter referred to as IBP) v2.5.1 with Fabric v2.2.0. You may experience issues with a different version of IBP. The fabric network created in the guide has one peer organization with one peer node and
one ordering organization with one orderer node. The ordering service utilizes the [Hedera Consensus Service](https://hedera.com/consensus-service) (HCS).

### 1. Prerequisites

1. [IBM Cloud account](https://cloud.ibm.com/registration)
1. [Hedera Testnet account](www.portal.hedera.com)
1. [`docker`](https://docs.docker.com/get-docker/)
1. [`docker-compose`](https://docs.docker.com/get-docker/)
1. [`git`](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
1. [`go`](https://golang.org/dl/)
1. [`helm`](https://helm.sh/docs/intro/install/)
1. [`kubectl`](https://kubernetes.io/docs/tasks/tools/)
1. [`jq`](https://stedolan.github.io/jq/download/) and [`yq`](https://kislyuk.github.io/yq/)
1. A domain name reserved for the orderer. It's required to generate a SSL certificate for the orderer
   so as to pass SSL hostname verification. Some webistes provide free domain names, e.g., duckdns.org,
   which is sufficient for dev/test purpose.

### 2. Create IBP Service on IBM Cloud

1. Go to https://cloud.ibm.com and log in with your credentials

1. Go to https://cloud.ibm.com/catalog, choose **Kubernetes Service**, configure the service as follows

  | Attribute                    | Value                  |
  |------------------------------|------------------------|
  | Plan                         | Standard cluster       |
  | Cluster type and version     | Kubernetes - 1.17.x    |
  | Environment                  | Classic infrastructure |
  | Location                     | Single zone            |
  | Default worker pool - flavor | 4 vCPUs 16GB RAM       |
  | Worker nodes                 | 2                      |

  click **Create** to create the cluster.

1. Set the local Kubernetes context to the new cluster. It's recommended to create a separate namespace
   for the fabric hcs orderer and set it as the default namespace:
   ```bash
   $ kubectl create namespace orderer
   $ kubectl config set-context --current --namespace=orderer
   ```

1. Create IBP service on the kubernetes cluster
  1. Go to https://cloud.ibm.com/catalog/services/blockchain-platform, make sure the region is the same as the kubernetes cluster and click **Create**.
  1. Once the service is created, click **Let's get setup!**
  1. Click **Next**, choose the kubernetes cluster just created, click **Next** and wait for the deployment to finish.

### 3. Create Managed IBP Components

In this section, we will create a CA for an organization which runs a fabric peer node and a CA for an organization which
runs an orderer node. For each CA, we will also register / enroll identities and create MSP definition. Note that the CAs,
identities, and the peer node will be managed by IBP, while other resources including the orderer node, the channel, and etc
will be managed manually.

#### 3.1 Create Org1

1. Open the deployed IBP service console.

1. Create CA for the organization **Org1**
  * Switch to the Nodes tab by clicking the ![](./imgs/nodes.png) icon
  * Click **Add Certificate Authority**
  * Choose **Create a Certificate Authority** and click **Next**
  * Provide `Org1 CA` as **CA display name** and click **Next**
  * Specify an **CA Administrator Enroll ID** of `admin` and CA Administrator Enroll Secret of `adminpw`, then click **Next**
  * Review the summary and click **Add Certificate Authority**

1. Associate **Org1** CA admin identity
  * In the Nodes tab, select **Org1 CA** once it is running (indicated by the green box in the tile)
  * Click **Associate identity** on the CA overview panel
  * On the side panel, select **Enroll ID**
  * Provide `admin` as the **Enroll ID** and `adminpw` as the **Enroll secret**. Use `Org1 CA Identity` as the
    **Identity display name**
  * Click **Associate identity** to add the identity into your IBP wallet and associate the admin identity with
    **Org1 CA**

1. Register the peer and org1 admin identities with **Org1 CA**
  * In the Nodes tab, select **Org1 CA**
  * Click **Register user**. Provide `peer1` as the **Enroll ID**, `peer1pw` as the **Enroll secret**, and `peer` as the **Type**, then click **Next**. On the next page, click **Register user**
  * Click **Register user**. Provide `org1admin` as the **Enroll ID**, `org1adminpw` as the **Enroll secret**, and `admin` as the **Type**, then click **Next**. On the next page, click **Register user**.

1. Create MSP for **Org1**:
  * Switch to the Organizations tab by clicking the ![](./imgs/orgs.png) icon
  * Click **Create MSP definition**. Provide `Org1MSP` as the **MSP display name** and `Org1MSP` as the **MSP ID**, then click **Next**
  * Choose `Org1 CA` as the **Root Certificate Authority**, then click **Next**
  * Provide `org1admin` as the admin **Enroll ID**, `org1adminpw` as the **Enroll secret**, and `Org1 Admin` as the **Identity name**, then click **Generate**. Once it's done, click **Export** to download the identity information json file. Click **Next**
  * On the review page, click **Create MSP definition**

1. Create a peer node for **Org1**
  * Switch to the Nodes tab
  * Click **Add peer**. Choose **Create a peer**, then click **Next**
  * Provide `peer1 org1` as the **Peer display name**, then click **Next**
  * Provide `Org1 CA` as the **Certificate Authority**, `peer1` as the **Peer enroll ID**, `peer1pw` as the
    **Peer enroll secret**, `Org1MSP` as the **Organization MSP**, `2.2.1-4` as the **Fabric version**, then click **Next**
  * Provide `Org1 Admin` as the **Peer administrator identity**, then click **Next**
  * On the summary page, click **Add peer**

#### 3.2 Create OrdererOrg

1. Open the deployed IBP service console.

1. Create CA for the organization **OrdererOrg**
  * Switch to the Nodes tab
  * Click **Add Certificate Authority**
  * Choose **Create a Certificate Authority** and click **Next**
  * Provide `OrdererOrg CA` as the **CA display name** and click **Next**
  * Specify an **CA Administrator Enroll ID** of `admin` and CA Administrator Enroll Secret of `adminpw`, then click **Next**
  * Review the summary and click **Add Certificate Authority**

1. Associate the **OrdererOrg** CA admin identity
  * In the Nodes tab, select the **OrdererOrg CA** once it is running (indicated by the green box in the tile)
  * Click **Associate identity** on the CA overview panel
  * On the side panel, select **Enroll ID**
  * Provide `admin` as the **Enroll ID** and `adminpw` as the **Enroll secret**. Use `OrdererOrg CA Identity` as
    the **Identity display name**
  * Click **Associate identity** to add the identity into your IBP wallet and associate the admin identity with
    **OrdererOrg CA**

1. Register the orderer and ordererorg admin identities with **OrdererOrg CA**
  * In the Nodes tab, select the **OrdererOrg CA**
  * Click **Register user**. Provide `orderer1` as the **Enroll ID**, `orderer1pw` as the **Enroll secret**, and `orderer`
    as the **Type**, then click **Next**. On the next page, click **Register user**
  * Click **Register user**. Provide `ordereradmin` as the **Enroll ID**, `ordereradminpw` as the **Enroll secret**,
    and `admin` as the **Type**, then click **Next**. On the next page, click **Register user**.

1. Create MSP for **OrdererOrg**:
  * Switch to the Organizations tab by clicking the ![](./imgs/orgs.png) icon
  * Click **Create MSP definition**. Provide `OrdererMSP` as the **MSP display name** and `OrdererMSP` as the **MSP ID**,
    then click **Next**
  * Choose `OrdererOrg CA` as the **Root Certificate Authority**, then click **Next**
  * Provide `ordereradmin` as the admin **Enroll ID**, `ordereradminpw` as the **Enroll secret**, and
    `OrdererOrg Admin` as the **Identity name**, then click **Generate**. Once it's done, click **Export** to download
    the identity information json file. Click **Next**
  * On the review page, click **Create MSP definition**

### 4. Download Crypto Materials

The crypto materials of the two MSPs, the MSP of `org1admin` and `ordereradmin`, and the MSP and TLS of the identity
`orderer1` are required to generate the system channel genesis block and the application channel creation transaction,
configure the orderer node, and sign / submit transactions with the peer command line tool.

#### MSP Definitions

To export the msp definition as a json file, for example, `Org1MSP`:

* Switch to the Organizations tab by clicking the ![](./imgs/orgs.png) icon
* Click `Org1MSP`
* Click the download icon to export MSP definition as a json file

Repeat the same for `OrdererMSP`.

### 5. Run prepare.sh

The script `prepare.sh` does the following:

* generates and organizes the required crypto materials
* creates HCS topic IDs for the system channel and the application channel
* generates `configtx.yaml` from the template with all input
* creates the genesis block and the application channel creation transaction
* creates kubernetes configmaps and secrets for the orderer
* installs the helm chart `fabric-hcs-orderer`

Example command line:

```bash
./prepare.sh --hcscli-config-file hedera_env_testnet.json  --orderer-ca-url https://n2e4187-ordererorgca.mycluster-dal10-b-506326-c9b9a2a4c0093f2aa988607d5e76da72-0000.us-south.containers.appdomain.cloud:7054 --orderer-hostname fabric-example.duckdns.org --orderer-admin-file ~/Downloads/OrdererOrg\ Admin_identity.json --orderer-msp-file ~/Downloads/OrdererMSP_msp.json --org1-admin-file ~/Downloads/Org1\ Admin_identity.json  --org1-msp-file ~/Downloads/Org1MSP_msp.json --peer1-hostname n162b18-org1peer1.mycluster-dal12-b-590253-c9b9a2a4c0093f2aa988607d5e76da72-0000.us-south.containers.appdomain.cloud
```

Important notes before running the script:

1. Please update `hedera_env_testnet.json` with your testnet account ID and private key. This is the
   configuration file for `hcscli` which creates HCS topic IDs for the hcs orderer
1. The orderer CA's url can be found in the `Info and usage` tab in IBP management console
   -> Nodes -> OrdererOrg CA
1. Peer1's hostname can also be found in its `Info and usage` tab

Once the script finishes successfully, the fabric hcs orderer should be deployed in the kubernetes cluster.

Before moving to the next step:

1. Update the reserved hostname for the orderer to point to the orderer service's public IP and make sure the
   hostname resolves successfully. To get the public IP:
   ```bash
   $ kubectl get service/dev-fabric-hcs-orderer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
1. Wait until the orderer pod's status is `running`, for example:
   ```bash
   $ kubectl get pods
   NAME                       READY   STATUS    RESTARTS   AGE
   dev-fabric-hcs-orderer-0   1/1     Running   0          109s
   ```

### 6. Create the application channel and install the fabcar chaincode

The steps to create the application channel, have the peer join the channel, and fabcar chaincode
lifecycle management are packed into a script. The script can be run inside a docker container with
fabric tools.

```bash
$ cd docker
$ docker-compose up -d cli
$ docker exec deploy-cli scripts/script.sh
```
