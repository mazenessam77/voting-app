from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import VPC, PublicSubnet, PrivateSubnet, InternetGateway, NATGateway, ELB
from diagrams.aws.compute import EKS, ECR, EC2
from diagrams.aws.database import DynamodbTable
from diagrams.aws.general import User, InternetAlt1
from diagrams.k8s.network import Ingress, Service
from diagrams.k8s.compute import Deployment, Pod
from diagrams.k8s.controlplane import API
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions

# Styles to match the requested diagram
graph_attr = {
    "splines": "ortho",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "fontname": "Helvetica",
    "fontsize": "16",
    "fontcolor": "#2D3436"
}

node_attr = {
    "fontname": "Helvetica",
    "fontsize": "12",
}

out_path = "/Users/macbookair/.gemini/antigravity/brain/3bd495e7-3136-494d-97e0-bef3ea83d97f/aws_infra_pro"

with Diagram(
    "High-Availability Voting App Microservices on AWS EKS", 
    show=False, 
    filename=out_path,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr
):

    users = User("Users")
    internet = InternetAlt1("Internet")
    
    users >> internet

    with Cluster("Amazon VPC", graph_attr={"bgcolor": "transparent", "pencolor": "black", "penwidth": "2"}):
        igw = InternetGateway("Internet Gateway")
        internet >> igw

        with Cluster("Availability Zones (AZ1 / AZ2)", graph_attr={"style": "dashed", "bgcolor": "transparent", "pencolor": "#f39c12", "penwidth": "2"}):
            
            with Cluster("Public Subnets", graph_attr={"style": "rounded,filled", "bgcolor": "#e8f5e9", "pencolor": "#2ecc71"}):
                nlb = ELB("AWS Network LB\n(Ingress)")
            
            igw >> nlb

            with Cluster("Private Subnets", graph_attr={"style": "rounded,filled", "bgcolor": "#e3f2fd", "pencolor": "#3498db"}):
                with Cluster("Amazon EKS Control Plane", graph_attr={"bgcolor": "transparent", "pencolor": "#e67e22"}):
                    eks_cp = API("EKS Core")

                with Cluster("Application Microservices (EKS Worker Nodes)"):
                    ingress_ctrl = Ingress("NGINX Ingress")
                    
                    with Cluster("Namespace: voting-app"):
                        fe = Pod("Frontend UI\n(Pod)")
                        auth = Pod("Auth Service\n(Pod)")
                        be = Pod("Backend API\n(Pod)")

                    # Routing
                    nlb >> ingress_ctrl
                    ingress_ctrl >> Edge(label="/") >> fe
                    ingress_ctrl >> Edge(label="/auth") >> auth
                    ingress_ctrl >> Edge(label="/api") >> be

                    with Cluster("Namespace: argocd"):
                        argocd = Pod("ArgoCD\nController")

    # Outside VPC
    with Cluster("AWS Data Tier", graph_attr={"bgcolor": "transparent", "pencolor": "none"}):
        dynamodb = DynamodbTable("Amazon DynamoDB\n(Votes Table)")
    
    be >> Edge(label="AWS SDK") >> dynamodb
    
    with Cluster("CI/CD Pipeline", graph_attr={"bgcolor": "transparent", "pencolor": "none"}):
        github = Github("GitHub Repo\n(Source & K8s)")
        ci = GithubActions("CI Pipeline")
        ecr = ECR("Amazon ECR")
        
    github >> Edge(label="Trigger") >> ci >> Edge(label="Push Image") >> ecr
    argocd >> Edge(label="Watch & Sync Manifests", style="dashed", color="blue") >> github
    
    ecr >> Edge(label="Pull image", style="dotted") >> fe
    ecr >> Edge(label="Pull image", style="dotted") >> auth
    ecr >> Edge(label="Pull image", style="dotted") >> be
