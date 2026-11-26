# durian-bank (두리안뱅크 배포)

"데이터는 안에, 서비스는 밖에": web은 AWS k3s, core-api는 OpenStack k3s, 고객 DB는 OpenStack DB VM.

```
고객 → ALB 443 → 워커 30080(Traefik) → web (AWS)
                                      └─ Tailscale(core-api /32, tcp 4000, 서비스 토큰) → core-api (온프렘) → DB VM 3306
```

| 폴더 | 클러스터 | 내용 |
|---|---|---|
| `overlays/aws/` | AWS k3s | web Deployment·Service·Ingress, NetworkPolicy(나가는 건 DNS + core-api 4000만) |
| `overlays/onprem/` | OpenStack k3s A | core-api Deployment, MetalLB Service, NetworkPolicy(나가는 건 DNS + DB VM 3306만) |
| `argocd/` | 각 클러스터 ArgoCD | Application 예시 (처음엔 수동 Sync) |
| `make-secrets.sh` | 둘 다 | Secret 만들기 (값은 저장소에 없음) |

## 배포 순서
1. DB VM: `bank/db/init/01-schema.sql` 실행, 앱 계정은 `02-app-user.sh`에서 `'durian_app'@'%'` → `'durian_app'@'10.30.20.%'`로 (k3s 노드에서만)
2. 주소 채우기: core-api MetalLB 주소(aws 2곳 + onprem 1곳), DB VM 주소(onprem 2곳)
3. 이미지: `bank-release.yml`이 main에 bank/가 바뀌면 GHCR에 올리고 `newTag`를 바꿈
4. GHCR 패키지가 비공개면 두 클러스터 `durian-bank` 네임스페이스에 `ghcr-pull` 시크릿
5. `make-secrets.sh` → ArgoCD Application 등록 → Sync
6. Tailscale: core-api 주소 /32를 워커 1대가 광고, ACL `tag:durian-master·worker → core-api:4000` 켜기 (방화벽 정의서 7.2)

## 확인 (웹서버 세팅 테스트)
- `https://<도메인>/health` → 200, 로그인·거래내역·이체
- 남의 계좌 주소 → 403(AUTH-403), 위조 토큰 → 401, 비밀번호 5회 실패 → 잠금
- AWS 워커 파드에서 `nc -zv <DB VM> 3306` → 실패 (NetworkPolicy + 보안그룹 + Tailscale 둘 다 막음)
- core-api에 서비스 토큰 없이 요청 → 401
