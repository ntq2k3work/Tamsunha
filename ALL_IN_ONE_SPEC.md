# TƯỜNG NHỎ — ALL-IN-ONE CODEX SPEC v2.0

> **Architecture update (ADR-002, 2026-10-23):** the owner has replaced Supabase/PostgreSQL with a Laravel API in `server/` and local MySQL. This decision supersedes DEC-12 and all Supabase-specific implementation details below. Product behavior, privacy, authorization, idempotency, transaction, and safety invariants remain normative; see [ADR-002](docs/ADR/ADR-002-laravel-mysql-api.md).

For best agent behavior, use the individual files in the zip at repository root (`AGENTS.md` auto-discovered). This consolidated file is an offline reference; detailed document precedence: MASTER > AGENTS > other documents.


---

# A — CODEX GOAL

SOURCE FILE: `CODEX_GOAL.md`

# GOAL FOR CODEX — IMPLEMENT TƯỜNG NHỎ END TO END

You are the primary engineering agent working in the repository root. Your mission is to implement a production-intended, beta-ready Android-first Flutter application named **Tường Nhỏ**, based EXCLUSIVELY on this repository's specifications. Do not reply with a plan only; **make code changes, run available tests, iterate and keep progressing** in reviewable milestones.

## Product goal
Tường Nhỏ is a Vietnamese, age-18+ anonymous journaling community. Authenticated members share **one persistent, infinite 2D wall**. Every person starts at an intelligent discovery location, can pan in all four directions and pinch to zoom, and can place a tiny pastel paper note in an empty spot they choose. The paper subtly flutters. Tapping a note animates it into a readable paper page. Another member can send one private predefined encouragement or start a private conversation; each participant can send at most THREE consecutive messages if the other has not replied, enforced on the server. Inbox, deletion, blocking/reporting and moderated operations support the three core actions. No public profiles, likes, comments, social feed, video or monetization.

## Start-up instruction
1. Read `AGENTS.md`, `README.md`, `docs/01_MASTER_PRODUCT_TECH_SPEC.md`, `docs/02_IMPLEMENTATION_PLAN.md`, `tasks/BACKLOG.md`, `docs/03_UX_AND_MOTION.md`, `docs/04_API_CONTRACT.md`, `docs/05_DATABASE_AND_SECURITY.md` and `docs/06_TEST_ACCEPTANCE.md`.
2. Inspect actual files, SDK versions and available tools. If repository currently contains only this spec kit, initialize the Flutter app in `app/`, the Laravel API in `server/`, and development scripts as the first task. Do not invent installation success.
3. Maintain `docs/PROGRESS.md` with current task, completed tasks, commands run, evidence, failures and next task. Maintain `docs/OPEN_QUESTIONS.md` for decisions needing a human.
4. Implement tasks in dependency order M0 → M1 → M2 → M3 → M4, using `tasks/BACKLOG.md` as checklist, with each task kept reasonably small. Do not jump to chat before wall POC and auth/security primitives exist.
5. For every task: implement, format, run static analysis, test, fix failures, record results, then move to next task. Commit checkpoints if repository and permissions permit. If unable to test on physical devices, clearly mark DEVICE QA pending; never call an unverified app production-ready.

## Critical implementation constraints
- UI: Flutter widgets for shell/compose/reader/inbox/chat, Flame only for world rendering. Tiny note surfaces remain unreadable until opened. Pastel chibi tactile paper. Subtle asynchronous motion, reduced motion switch.
- Shared wall: global integer cell coordinates, one occupancy per cell, position never shuffled. Viewport tile pagination, culling, zoom LOD, caching. Randomize only discovery entry point, biased toward underserved/new notes. Posting suggests free regions and user chooses cell. No endless bottom-scrolling feed.
- Data: use authenticated Laravel API operations for note placement, daily quota, content edits, encouragement and message writes; enforce them in atomic MySQL transactions with idempotency. Do not trust client counts/identities or expose a MySQL connection to the app.
- Identity: no author_id from wall/detail/public endpoints, no arbitrary lookups of other profiles. Pair-level conversation can incidentally link separate notes to a writer; do not claim per-note unlinkability.
- Safety: limit abuse, moderation/report/block flows, no public exposure of harmful content pending review, 18+ gating, privacy/terms/account deletion; no production beta without moderation owner process.
- Tests: negative RLS, two users collide on same cell, concurrent 4 messages, duplicate requests, note quota after deletion, unauthorized inbox reads, disabled-chat, blocked participants, UI gesture race conditions.

## Stop/approval gates (not ordinary coding blockers)
Ask the owner before: paying for services, enabling production billing, acquiring credentials, publishing to stores, destructive data migrations, legal interpretation/sign-off, making a publicly accessible beta, or introducing new paid dependencies. If credentials or device unavailable, complete mock/local-independent tasks and write exact setup instructions. Do not fabricate access to stores/devices.

## Definition of completion
Every task M0–M4 is implemented, has passing automated tests in an available environment, and no open high-severity security/blocking issues. A physical-device performance report, public beta moderation plan and store/legal owner signoff are separately required. If these external gates remain unmet, end with `IMPLEMENTED — RELEASE BLOCKED`, list exact blockers and next human actions; do not say 'shipped'.

## Immediate instruction
Begin with `M0-1` (repository/app foundation). Create `docs/PROGRESS.md` if absent, record toolchain detected, then implement M0-1 and continue sequentially as long as the environment and approval gates allow. Do not stop merely to ask if you should continue between normal coding tasks.


---

# B — AGENT RULES

SOURCE FILE: `AGENTS.md`

# AGENTS.md — Tường Nhỏ (rules for Codex)

Project: Vietnamese adult-only anonymous journaling mobile app with one shared, infinite 2D wall of pinned notes, encouragement and limited private chat. **Treat `docs/01_MASTER_PRODUCT_TECH_SPEC.md` as the canonical behavior specification.**

## Read before touching code
1. `README.md`
2. `docs/01_MASTER_PRODUCT_TECH_SPEC.md` (product, behavior, security invariants)
3. `docs/02_IMPLEMENTATION_PLAN.md` (milestone dependency order)
4. `docs/03_UX_AND_MOTION.md`, `docs/04_API_CONTRACT.md`, `docs/05_DATABASE_AND_SECURITY.md` as relevant
5. `docs/06_TEST_ACCEPTANCE.md`, `docs/07_DECISION_REGISTER.md`.

If docs conflict: `docs/01_MASTER_PRODUCT_TECH_SPEC.md` > this AGENTS.md > other docs. If a conflict materially affects security/privacy or user-facing behavior, record it in `docs/OPEN_QUESTIONS.md` and choose the **safer, smaller** implementation until the owner decides. Do not quietly reinterpret requirements.

## Locked product decisions
- Exactly ONE shared persistent 2D world, fixed global integer cell coordinates, **never a personalized scrambled fake layout or scroll feed**.
- User pans in X/Y, pinches to zoom, opens little paper to read, composes note, **chooses an unoccupied slot to pin**. Spawn/discovery location may change by visit; note positions DO NOT.
- Visual character: warm chibi/pastel hand-crafted paper; subtle independent flutter, paper-like easing, no shiny cards/plastic look; respect reduced motion.
- Anonymous *to other users* (not to the service); never expose author/user IDs in wall/detail DTOs. No public usernames, followers, likes, public comments, photos or payments.
- One journal note per user per Vietnam calendar day (default beta limit). Only the note owner may edit/delete. Paper stays until deleted/moderated; old paper visually ages.
- Encouragement is ONE of five predefined templates; one per sender/note; private to the recipient.
- **Per user-pair conversation**, maximum **3 consecutive messages from one participant without a response**, enforced atomically on the backend; never reset through another note, re-login or local deletion.
- Author may turn OFF new chat from each note; blocking and reporting must work.
- Android-first, iOS-capable Flutter app. Mobile UI is not a responsive website.

## Required stack and architecture
- Flutter (Dart), Flame only for wall/game world, Riverpod, GoRouter.
- Laravel 13 API monolith, MySQL 8.4/InnoDB, Sanctum mobile bearer tokens, and Reverb private authorized channels for invalidation signals.
- Integer cells/tiles for MVP; no microservices or Kubernetes. MySQL is reachable only by the server; local development binds it to loopback.
- Feature-first layout `app/lib/features/...`; backend migrations/services/tests in `server/`; Flutter domain contracts remain independent of transport.
- Pin versions compatible with current stable SDK; commit `pubspec.lock`; document actual installed versions in `docs/ADR/ADR-001-toolchain.md`. Do not fabricate version numbers or APIs.

## Security invariants — NON-NEGOTIABLE
- Backend derives actor identity from verified auth context; client cannot submit `author_id`, `sender_id` or `recipient_id` to impersonate someone.
- Client code has only the API base URL and user bearer token; never include MySQL, SMTP, FCM service-account, or moderator secrets in the app. `.env` is gitignored and `.env.example` contains placeholders.
- No direct table API: expose allow-listed operations and least-privilege DTO projections. Every operation authorizes in Laravel from the verified session; policy and ownership checks are tested.
- Atomic transactions, unique occupancy, idempotency for `place_note`, `send_message`, `send_encouragement`.
- Report, block, delete account, consent, moderation and admin audit must exist **before inviting strangers to beta**.
- Do not send note/chat bodies or third-party identifiable info in analytics, push preview, crash logging, or public Realtime broadcasts.
- App does not claim E2EE, therapy, emergency intervention, perfect anonymity, or guaranteed human replies.

## Codex working agreement
- Start from the earliest incomplete task in `tasks/BACKLOG.md` and respect dependencies. Complete one task at a time and update `docs/PROGRESS.md` with commands run and actual results. Continue task-by-task if `CODEX_GOAL.md` asks for autonomous progress; pause ONLY at external account/credential, legal, cost, irreversible deployment or other permission gates.
- Each unit of work: inspect repository, state approach briefly, change minimal files, run format/analyze/tests as tools allow, document result (PASS/FAIL/NOT RUN and why), update progress.
- No fake tests, fake screenshots, invented integrations, hardcoded mock data behind production flags, or silently skipping safety requirements.
- Use testable repository interfaces; unit-test domain rules and screen/world transforms; write negative-permission and concurrency SQL tests.
- Do not manually edit production data/schema; create migrations; never deploy to production without explicit owner authorization.
- If Flutter SDK or local MySQL tooling is missing, scaffold valid code/docs, run available static checks, and state precise unverified tests; NEVER say tests passed when they weren't run.
- Ensure all user-facing Vietnamese strings are correctly accented; explain errors politely.
- Every milestone must leave a runnable state, clean build configuration, no untracked secrets and an explicit release gate checklist.

## End-of-task response template
**Task ID / Goal**; **Files changed**; **Commands executed and results**; **Screens/tests verified**; **Security/privacy concerns**; **Known gaps/blockers**; **Next task ID**. If not run, mark NOT RUN with reason.


---

# C — MASTER PRODUCT & TECH SPEC

SOURCE FILE: `docs/01_MASTER_PRODUCT_TECH_SPEC.md`

# TƯỜNG NHỎ — MASTER PRODUCT & ENGINEERING SPECIFICATION

**Phiên bản:** 1.0.0 · **Ngày:** 2026-10-23 · **Trạng thái:** Development baseline / MVP · **Ngôn ngữ:** Tiếng Việt  
**Đối tượng:** Một lập trình viên dùng AI coding agent, có thể phối hợp QA/design sau này.

> Đây là nguồn yêu cầu chuẩn duy nhất cho MVP. Agent **không được tự ý thêm tính năng**, thay đổi quy tắc sản phẩm, làm lộ định danh hoặc nới lỏng phân quyền. Khi tài liệu có mục `ASSUMPTION`, triển khai mặc định như ghi và ghi lại trong ADR; không tự tạo lựa chọn mới.

---

## 0. Executive summary

Tường Nhỏ là app iOS/Android để người trưởng thành viết nhật ký dưới dạng **tờ giấy nhỏ** rồi **tự chọn khoảng trống để dán lên một bức tường 2D chung, có thể khám phá theo bốn hướng**. Những người khác có thể chạm vào giấy để đọc, **gửi một lời động viên có sẵn** hoặc **mở cuộc trò chuyện riêng**. Mỗi phía được gửi **tối đa 3 tin nhắn liên tiếp nếu bên còn lại chưa trả lời**. Không có like công khai, follow, feed video, ảnh, bình luận công khai, ranking hay matching/hẹn hò.

**Giá trị cốt lõi:** Người viết có cảm giác được lắng nghe, người đọc có thể quan tâm mà không bị ép trò chuyện. UI chibi tinh tế, giấy mềm và animation nhẹ, không biến thành game ồn ào.

**Phạm vi bản 1.0:** Android-first, code Flutter dùng được cho iOS; thử nghiệm closed beta có kiểm duyệt trước khi phát hành công khai. Nội dung tiếng Việt, người dùng 18+, quyền riêng tư rõ ràng.

## 1. Những quyết định đã khóa

| ID | Quyết định |
|---|---|
| DEC-01 | **Một world chung duy nhất**: tất cả người dùng đọc cùng note và cùng tọa độ, không xáo trộn bố cục riêng từng người. |
| DEC-02 | World không có cạnh thị giác; pan X/Y, pinch zoom. Điểm đến lúc mở app được chọn theo thuật toán, **không** mặc định `(0,0)`. |
| DEC-03 | Người viết chọn khoảng trống để dán, backend có quyền từ chối vị trí bị chiếm; không có ghi đè lên giấy người khác. |
| DEC-04 | Note công khai **ẩn danh với cộng đồng**, nhưng backend liên kết với user thật để phân quyền/an toàn. |
| DEC-05 | Note có thể tồn tại cho đến khi tác giả xóa hoặc bị kiểm duyệt; ngoại hình phai màu theo tuổi, nội dung không tự mất. |
| DEC-06 | Chỉ 3 tương tác xã hội chính: đăng note, động viên, chat; tính năng quản trị/an toàn là bắt buộc. |
| DEC-07 | Một tài khoản chỉ tạo tối đa **1 note mỗi ngày theo giờ Việt Nam**, kể cả xóa note đã tạo. Đây là giới hạn thử nghiệm. |
| DEC-08 | Một tài khoản gửi **tối đa 1 động viên/note**, sử dụng danh sách câu định sẵn trong MVP. |
| DEC-09 | Một cặp user có tối đa **1 conversation**, phát sinh từ một note; áp dụng giới hạn 3 tin **theo cặp** và theo chiều người gửi. |
| DEC-10 | Người viết có thể tắt nhận chat theo từng note, vẫn có thể nhận động viên. |
| DEC-11 | Không hiển thị public profile, follower count, reaction count, typing status, last seen, read receipts. |
| DEC-12 | Flutter + Flame + Riverpod + GoRouter + Laravel API + MySQL/InnoDB + Reverb; one backend monolith, no microservices. See ADR-002. |

### 1.1 Các giá trị mặc định cần đo lại (ASSUMPTIONS)

- Note: tối đa **1.000 Unicode grapheme clusters**; không cho nội dung rỗng. Server giới hạn **6 KB UTF-8** để tránh payload bất thường.
- Giấy có cùng kích thước logic 118 × 145 world units; lưới vô hình **180 × 180** units/ô; biến thiên rotation ±5°, offset ±6 units; giao diện có thể zoom min **0.45**, max **2.2**, mặc định khoảng **0.80** sau khi đo trên màn hình thật.
- Tile: **8 × 8 ô** tương đương 1.440 × 1.440 world units. Tập hợp note gần camera được query theo tile, không query cả world.
- Vùng bắt đầu: ưu tiên nơi có note và còn ít nhất 3 ô trống. Chọn theo trọng số `40% note chưa nhận động viên, 35% note mới, 25% khu vực ngẫu nhiên có note`; có cooldown tránh chỉ đưa người dùng tới vài cụm.
- Hiệu ứng flutter: biên độ góc ~1–2°, mỗi note lệch pha, chu kỳ ~3–7s, cường độ tăng nhẹ theo gió giả lập; có chế độ reduce motion.
- Note edit: được phép sửa trong **30 phút kể từ lúc đăng** và chưa có tương tác; sau đó chỉ có thể xóa. Quyết định này ngăn sửa nội dung sau khi đã có người động viên hoặc bắt đầu chat.
- Thời gian hiển thị tại UI: local của thiết bị; quota đăng note dùng `Asia/Ho_Chi_Minh` **ở server**.
- Ngưỡng và tỷ lệ khám phá chỉ là tham số cấu hình, không phải dữ liệu chứng minh sản phẩm.

### 1.2 Không nằm trong MVP (explicit non-goals)

Ảnh/video/audio, đính kèm file, emoji/sticker trả phí, bình luận dưới note, follow, profile công khai, like/tim công khai, bảng xếp hạng, tìm người gần đây, phân phối quảng cáo, AI viết hộ nhật ký, AI giả làm người động viên, gợi ý bạn bè, livestream, nhắn tin nhóm, tự động dịch ngôn ngữ, E2EE, multiplayer game world realtime từng pixel, marketplace.

---

## 2. Đối tượng, vai trò, quyền

**Visitor chưa đăng nhập:** onboarding/điều khoản/chính sách; không đọc note hoặc chat trong MVP. **User đã xác thực và đủ 18+:** khám phá note đã duyệt, tự viết, động viên, chat theo quyền, báo cáo/chặn, quản lý dữ liệu của mình. **Moderator:** xem hàng đợi xử lý, có quyền ẩn nội dung/chặn theo phạm vi admin. **Admin:** quản lý cấu hình, audit, khiếu nại, xóa dữ liệu/retention. Không dùng chung quyền moderator với tài khoản cá nhân test thông thường.

Không dùng tên/nickname/avatar public. Trên giao diện chat chỉ dùng nhãn trung lập `Bạn` và `Người viết`; không công khai `user_id`, email, phone, profile, metadata thiết bị hoặc vị trí thật. Cần giải thích trong onboarding: *Ẩn danh trước người dùng khác, không phải ẩn danh với nhà cung cấp dịch vụ.*

**Lưu ý quyền riêng tư:** Một conversation duy nhất theo cặp người dùng có thể khiến người đã trao đổi nhận ra hai note khác nhau thuộc cùng một tác giả nếu họ lần lượt chat từ cả hai note. Đây là trade-off có chủ ý của MVP để ngăn vượt giới hạn 3 tin; KHÔNG quảng cáo rằng mỗi note hoàn toàn không thể bị liên kết. Nếu cần mạnh hơn, nghiên cứu mô hình chat theo note với hạn mức người nhận không lộ ra, ở bản sau.

---

## 3. Information architecture & screen inventory

Điều hướng mobile gồm **tối đa 3 entrypoints**: `Tường` (main), `Hộp thư` (encouragement + chat), `Của tôi` (notes, cài đặt). Nút `+` dán giấy nổi trên tường. Thanh navigation trông như đồ họa paper/chibi nhưng dùng native Flutter widgets để dễ truy cập.

| Screen ID | Màn hình | Thành phần/logic | Trạng thái bắt buộc |
|---|---|---|---|
| S00 | Splash/bootstrap | kiểm tra session, app version, eligibility | loading, offline, blocked |
| S01 | Welcome/auth | tên app, slogan, đăng nhập, điều khoản/độ tuổi | signed-out, invalid OTP |
| S02 | Onboarding | cách kéo tường, viết, động viên, riêng tư, cộng đồng | new/complete |
| S03 | Infinite Wall | camera, notes, nút `+`, khám phá góc khác, trở về note của tôi, hộp thư | loading, populated, sparse, offline, error |
| S04 | Open Note | tờ giấy bay ra, nội dung đầy đủ, thời gian tương đối, 2 CTA | own note, other note, removed, chat disabled |
| S05 | Note Composer | textarea, counter, 5 màu giấy, bật/tắt chat | draft, invalid, publish preview |
| S06 | Placement Mode | kéo note nổi vào ô trống; ghost overlay cho vị trí hợp lệ | valid, occupied, network race, cancelled |
| S07 | Encouragement | 5 mẫu động viên; confirm, success | already sent, own note, blocked |
| S08 | Inbox | hai tab `Lời động viên`, `Tin nhắn` | empty, unread, list |
| S09 | Conversation | lịch sử, input, hiển thị quota 3 tin | 0/3..3/3, blocked, conversation closed |
| S10 | My Notes | danh sách note của tôi, jump to location, delete/edit | empty, deleted, archived-by-moderation |
| S11 | Privacy/Settings | đăng xuất, tắt notification, reduced motion, chính sách, xóa tài khoản | offline, deletion pending |
| S12 | Report/Block | chọn lý do, xác nhận, chặn user | success, duplicate report |
| ADM | Admin console | reports, notes/messages flagged, actions, audit logs | role gated |

### 3.1 Design system

- Tone: đáng yêu vừa phải, chibi editorial, không bóng nhựa, không neon; nền kem có texture tinh tế, bảng tường không có mép nhìn thấy.
- Color tokens ví dụ: `canvas #F3E8D7`, `ink #55483E`, `pink #F4D5D8`, `butter #F8E5B2`, `sage #DCE7D6`, `blue #DAE6F1`, `lilac #E9E0F3`; xác định tương phản sau khi test accessibility.
- Giấy có khía cạnh hand-drawn, 2–3 mẫu băng dính/ghim, viền không đồng đều nhẹ, bóng rất ít, texture tileable kích thước nhỏ; asset phải có license hợp lệ.
- Note trên tường: **không đọc được nội dung**; chỉ vài nét mực giả hoặc doodle, chạm mới fetch nội dung thật. Không hiển thị preview bí mật trong tiles API.
- Animation mở: vị trí ban đầu đúng giấy đã chạm → nổi khỏi ghim → scale và xoay về 0° → tờ giấy lớn giữa màn hình (250–450ms, spring/ease theo performance test), nền tường mờ nhẹ; đóng về đúng camera/world position nếu còn hợp lệ.
- Giấy phấp phới tự nhiên không đồng pha; hiệu ứng chỉ áp dụng note trong vùng nhìn. `Reduce motion` giảm hoặc tắt flutter và chuyển cảnh nhanh.
- Bấm mục tiêu tương tác >=44–48 logical pixels; responsive, text-scale, VoiceOver/TalkBack, tránh chỉ dựa vào màu.
- Layout tham chiếu chính: 390×844 logical px; phải test 360×800, 430×932 và iOS Dynamic Type / Android font scaling.

### 3.2 Wireflow cụ thể

**A. Xem/đọc:** S00 → S01 nếu chưa login → S02 nếu chưa onboard → S03 → tap paper → S04 → CTA `Động viên` (S07) hoặc `Nhắn tin` (S09). Tap giấy của chính mình → `Sửa` (nếu được), `Xóa`, `Về vị trí` thay hai CTA.

**B. Đăng:** S03 `+` → S05 viết và chọn màu → `Chọn chỗ dán` → backend đề xuất nearby region còn ô trống nếu cần → S06 kéo giấy → `Dán tại đây` → server xác nhận → animation giấy ghim → hiện S03 focus note vừa dán. Back/cancel: giữ draft cục bộ (không công khai).

**C. Động viên:** S04 → S07 → chọn 1/5 câu → send → trạng thái `Đã gửi`, không cộng like public → chủ note thấy mục mới trong Inbox; không cho tự động gửi lại.

**D. Chat:** S04 → `Nhắn tin`; nếu note `allow_chat=false`, ẩn hoặc disable và giải thích nhẹ. Khi mở conversation từ note, không tạo message cho đến khi người dùng thực sự gửi. Không show author name/public ID. User có thể report/block qua overflow menu.

**E. Khám phá:** nút `Góc khác` → camera chuyển sang region đã chọn (fade/pan ngắn); ưu tiên note ít tương tác, note mới và một phần ngẫu nhiên. `Note của tôi` → list hoặc nearest note của user → camera animate tới tọa độ note.

---

## 4. Business rules (normative)

### 4.1 Account & session

- MVP: đăng nhập email OTP qua Laravel API và configured mail transport; không lưu OTP dạng rõ, phải có expiry, attempt limit và rate limit. Không cho nickname công khai. Tuổi >=18 qua khai báo và điều khoản; **khai báo tuổi không phải xác minh tuổi**. Bổ sung xác thực danh tính theo yêu cầu pháp luật áp dụng trước khi phát hành công khai nếu bắt buộc.
- `profiles` được tạo cho user đã xác thực, `status = active|suspended|deleted_pending`; tài khoản suspended không được post/chat, chỉ có thể logout/xem thông báo xử lý nếu được phép.
- App launch reconnect session an toàn; logout xóa private caches / credentials của phiên; không in token vào logs.

### 4.2 Note

- Cho phép 1 note **được tạo**/ngày, kể cả xóa trong ngày; backend kiểm tra ngày VN bằng timestamp đáng tin cậy. Chặn tác giả tự động viên/chat với mình.
- `content` 1–1.000 grapheme, trim; giữ dòng xuống; encode an toàn; plain text, không Markdown/HTML/URL clickable, không image/attachment. Server normalize Unicode NFC và từ chối payload nghi ngờ.
- Note status: `pending_review`, `published`, `hidden`, `deleted`; **chỉ published** hiển thị world. Chỉ một note được lưu thành công (`pending_review`/`published`) mới tiêu tốn lượt viết trong ngày; payload bị reject trước khi lưu không tiêu quota. Note pending vẫn giữ cell đã chọn cho đến khi được duyệt, xóa hoặc xử lý hết hạn moderation theo runbook. Có thể pre-moderation hoặc post-moderation tùy rủi ro; mặc định beta dùng moderation filter trước khi published + manual queue khi cần.
- `allow_chat` lấy theo lúc đăng và chủ sở hữu có thể tắt sau. Tắt chat chặn khởi tạo mới và chặn gửi vào hội thoại gắn với note nếu chưa có kết nối đã được chấp thuận; đối với conversation đã hoạt động, người viết phải có action `Đóng trò chuyện`/`Chặn` để ngắt giao tiếp rõ ràng. Để đơn giản MVP: tắt chat ở note làm **không thể mở chat mới từ note đó**, nhưng không tự ngắt các conversation đã có từ trước, và UI nói rõ điều này.
- Sửa content trong 30 phút **và** `encouragement_count=0`, không có conversation phát sinh từ note; sửa phải kiểm duyệt lại; tác giả có thể xóa bất kỳ lúc nào. Khi xóa, gỡ khỏi tile/đọc public ngay, giữ tombstone nếu thread tồn tại (`Tâm sự này không còn hiển thị`) để không phá lịch sử chat; quyền xóa dữ liệu được thực thi theo retention/legal policy.
- Note tuổi >7/30/90 ngày chỉ thay đổi style/fade qua shader/tint (không làm mất khả năng đọc). Không tự xóa.

### 4.3 Encouragement

- 5 câu mặc định, khóa ID: `LISTEN`, `TOMORROW`, `TRIED`, `THANKS`, `HUG`; nội dung quản lý bằng localization assets. Không free-text ở MVP để giảm harassment; không có count công khai.
- Unique `(note_id, sender_id)`, không tự động viên note của mình, không động viên note đã ẩn/xóa, không gửi khi một trong hai đã chặn bên kia. Không lặp khi retry (idempotent response).
- Owner thấy câu + relative time + note ref trong hộp thư, **không thấy danh tính người gửi**. Sender không nhận tín hiệu người kia đã đọc động viên.

### 4.4 Chat — 3 consecutive messages

- Một `conversations` cho mỗi unordered pair user `(participant_low, participant_high)`, unique. `source_note_id` lưu note tạo cuộc chat đầu tiên; không cho client tự chỉ định người nhận qua `user_id`.
- Trạng thái `active`, `closed_by_user`, `blocked`, `suspended`. Khi recipient từ chối/đóng, sender không gửi thêm được.
- Quy tắc cốt lõi: `last_sender_id` và `streak_count` lưu trên conversation. Sender bằng last_sender → `streak_count + 1`; nếu sender khác → `streak_count=1`, `last_sender_id=sender`. Nếu same sender và `streak_count >=3` → trả `MESSAGE_LIMIT_REACHED`, **không insert**.
- Khi A gửi 3 và B chưa reply: A không được gửi tin thứ 4; B vẫn có quyền phản hồi (miễn conversation hợp lệ). Khi B gửi 1, A được gửi lại tối đa 3 liên tiếp; B cũng chịu cùng giới hạn nếu tiếp tục gửi. Rule áp dụng trên cặp user bất kể origin note; xóa local chat không reset.
- Text <=1.000 grapheme, plain text, anti-spam/rate-limit, không upload media/link tự động. Tin nhắn gửi vào hàng kiểm duyệt vẫn tính là một tin đã gửi trong streak để chặn spam; khi bị ẩn thì giữ audit và không tăng lại quota. Nếu bị lọc trước khi lưu vì validation cứng, không trừ lượt. Mỗi request `client_request_id UUID`, unique `(sender_id, client_request_id)` để retry không nhân bản.
- Dùng một DB transaction khóa hàng `conversations ... FOR UPDATE` hoặc transaction advisory lock trên pair; check membership + block + status + streak + insert + update + outbox event atomically.
- Bắt đầu chat bằng thao tác `start_conversation_from_note(note_id)`; API trả opaque conversation ID, không trả author ID. Nếu conversation đã tồn tại, trả cùng conversation. **Điều này có thể để người chat suy luận các note chung tác giả: xem phần privacy trade-off.**
- Không hiển thị last seen, typing, read receipt. Không liên tục thông báo khi mỗi tin trong streak đến; gộp notification khi hợp lý.

### 4.5 Block & report

- `block_user_from_note(note_id)` và `block_user_from_conversation(conversation_id)` qua server, không phơi user ID khác. Chặn **hai chiều** tương tác giữa cặp: gửi tin, encouragement, start chat đều bị từ chối; chặn không làm người kia mất quyền đọc các note công khai đã published trừ khi admin áp dụng lọc nội dung; nếu bị chặn, app không cần tiết lộ danh tính chủ note.
- Report reason: `harassment`, `hate`, `sexual_content`, `self_harm_concern`, `personal_info`, `spam`, `other`. Report note/conversation/message; user chỉ xem trạng thái report của chính mình, admin review chi tiết.
- Abuse handling: post filter server-side, rate limiting, repeated abuse suspension, admin queue, audit. Quy trình cho nội dung khủng hoảng tránh hứa hẹn có người theo dõi 24/7; cung cấp hướng dẫn liên hệ người đáng tin/cơ quan cứu trợ phù hợp. Không dùng AI tự xưng chuyên gia tâm lý.

---

## 5. Infinite Wall: toán học, bố cục, khám phá

### 5.1 Coordinate model

- World dùng tọa độ rời rạc theo `cell_x INT`, `cell_y INT`, mỗi cell **180×180 world units**. Client tính center `(cell_x*180, cell_y*180)`. Phần thay đổi `offset_x/y` trang trí được tạo **deterministic** từ `note_id` seed, không cho ảnh hưởng collision. `rotation_deg` deterministic ±5°.
- Paper logical rect 118×145 => cả bounding box sau rotate tối đa ~131×155, vẫn lọt cell 180 (khoảng trống đủ để tap). Có thể bố trí texture phụ ở ngoài nhưng không chặn tap của note bên cạnh.
- Tile coords `tile_x = floorDiv(cell_x, 8)`, `tile_y = floorDiv(cell_y, 8)` (floorDiv cho số âm! `-1 / 8 = -1`). Tile fetch: từ `visibleWorldRect` + 1 tile margin; giới hạn concurrency và cache LRU.
- `notes` có unique partial `(cell_x,cell_y)` WHERE `status IN ('pending_review','published','hidden')` để tạm giữ ô; khi status `deleted` giải phóng ô. Không reuse vị trí khi note hidden do kiểm duyệt cho đến khi xử lý xong.
- Không dùng float vô hạn để định danh vật lý: index tile/cell dùng integer 64-bit hoặc int PostgreSQL trong hạn mức kiểm soát. Khi camera di chuyển quá xa, dùng **floating-origin rendering**: giữ absolute cell coords ở state và render local offsets gần camera tránh precision loss.

### 5.2 Tải note & cache

- `list_wall_tiles(bounds, max_items, page_cursor)` chỉ trả `published` và các trường render tối thiểu `id, cell_x, cell_y, style_seed, paper_color, published_at`. **Không trả `author_id`, `content`, email, admin status.**
- `get_note_detail(note_id)` mới trả `content`, thời gian, allowed CTAs. Với own note trả capability owner flags riêng; không bao giờ trả public user ID của tác giả.
- Camera move/pinch dùng local render ngay. Networking được debounce 150–250ms hoặc trigger khi camera sắp ra khỏi loaded tile; stale request có thể cancel/ignore; LRU giới hạn tiles in-memory (khởi đầu ~30, điều chỉnh theo memory).
- Khi có >max note trong view zoom xa, chuyển `LOD0`: vẽ màu giấy/density clusters; `LOD1`: texture giấy và pin; `LOD2`: flutter và chi tiết nét mực. **Không render hàng nghìn widget Flutter cho note**, dùng Flame components/sprites.
- Tile invalidation: khi dán/xóa note, cập nhật local tile và broadcast sự kiện **tối thiểu** theo tile, có subscription tối đa các tile quanh camera hoặc dùng TTL refresh. Không subscribe mọi tile của world.

### 5.3 Lựa chọn khu vực khởi đầu

- Mỗi region = 1 tile 8×8 cell. `wall_regions` là thống kê cache có thể rebuild: `published_count`, `free_count`, `unencouraged_count`, `recent_count`, `last_featured_at`, `status`.
- Khi vào app: server `get_discovery_target(seed)` chọn region có >=N note published và >=3 free cells; loại region bị abuse/under review; weighted categories unencouraged/new/random (40/35/25 ASSUMPTION); chống lặp cùng user trong phiên bằng recent region IDs local + server hint.
- Nếu chưa đủ nội dung: đưa vào cụm có note seed thật từ beta (không giả người động viên), không teleport ra vùng trống. Nếu toàn hệ thống chưa có note, hiển thị onboarding empty world và lời mời viết note đầu tiên.
- Người dùng có thể pan đến vùng khác hoặc dùng `Đến góc khác`. Không hứa mỗi note chắc chắn được đọc; ưu tiên công bằng để tăng cơ hội.

### 5.4 Placement state machine

`DRAFT → PLACEMENT_PREVIEW → SUBMITTING → (PUBLISHED | PENDING_REVIEW | OCCUPIED | ERROR)`.

1. User viết content, màu giấy, `allow_chat`; giữ local draft.
2. Khi vào placement, có thể tiếp tục vùng đang xem nếu còn trống; nếu không server trả `suggest_placement_regions` ưu tiên gần camera/cụm hoạt động còn chỗ.
3. User kéo ghost note; screen → world → snap nearest cell; client kiểm tra cached occupancy (chỉ để preview), có thể hiển thị `Chỗ này đã có giấy`.
4. Tap `Dán`: request `client_request_id`, `cell_x/y`, content; server validates auth, quota, moderation, blocks, bounds, unique occupancy; transaction atomic.
5. Nếu occupied: trả `SLOT_OCCUPIED` + tối đa 3 tọa độ nearby còn trống (không tự dời note mà không hỏi người dùng). Client hiện ghost ở vị trí gợi ý, xác nhận lại.
6. Nếu pending review: hiển thị `Đang được kiểm tra`, note chưa công khai. Nếu published: broadcast tile invalidation và focus paper.
7. Retry cùng request ID phải trả cùng kết quả; quota không bị trừ hai lần.

### 5.5 Realtime strategy

- Chat/inbox realtime: Laravel Reverb private channels theo conversation/user với authorization callback kiểm tra participant; chỉ push signal `{event_type}` rồi client fetch canonical records qua API. Không broadcast nội dung nhạy cảm hoặc định danh người khác.
- Wall: không phải game multiplayer realtime frame-by-frame. Có thể refresh tile sau khi nhận invalidation, khi focus lại app, và theo TTL. Không emit camera/pointer mỗi frame.
- Offline: người dùng vẫn pan trong vùng tile đã cache và xem nội dung note đã được mở trong phiên (nếu policy cho phép), nhưng không dán/gửi/chat khi offline. Không để nội dung riêng vào persistent cache không mã hóa.

---

## 6. Data model chi tiết

Dùng UUID cho IDs, `timestamptz`, snake_case, migrations versioned; quản lý timezone phía server. Dưới đây là **data dictionary**; AI sẽ tạo SQL migrations và test, không đoán thiếu cột/constraints.

### 6.1 `profiles`

- `user_id uuid PK references auth.users(id)`, `status text CHECK(active,suspended,deleted_pending)`, `adult_confirmed_at timestamptz`, `terms_version text`, `terms_accepted_at`, `onboarded_at`, `notifications_enabled boolean DEFAULT false`, `created_at`, `updated_at`.
- `user_id` chỉ owner/admin được đọc trong bảng; **không có public profile endpoint**.

### 6.2 `notes`

- `id uuid PK`, `author_id uuid NOT NULL`, `content text NOT NULL`, `content_version int DEFAULT 1`, `paper_color text CHECK (...)`, `style_seed int NOT NULL`, `cell_x bigint`, `cell_y bigint`, `status text`, `allow_chat boolean DEFAULT true`, `review_reason text NULL`, `created_at`, `updated_at`, `published_at`, `deleted_at`.
- `creation_day_vn date assigned server-side` để unique `(author_id, creation_day_vn)` cho mọi lần tạo kể cả note deleted. Tránh unique thiếu hiệu lực sau khi delete; có thể lưu ledger `daily_note_creations(user_id, day_vn, note_id UNIQUE...)` và transaction insert ledger trước/đồng thời với note.
- Indices: partial unique trên cell đang chiếm; `notes(status, cell_x, cell_y)` và/hoặc `notes(tile_x,tile_y,status)` có tile columns persisted/generated; `(author_id,created_at DESC)` phục vụ My Notes. Index enum/status cho moderation.

### 6.3 `encouragements`

- `id uuid PK`, `note_id uuid FK`, `sender_id uuid FK`, `template_key text CHECK in five keys`, `created_at`, `client_request_id uuid`, unique `(note_id,sender_id)`; unique `(sender_id,client_request_id)`.

### 6.4 `conversations`

- `id uuid PK`, `participant_low uuid FK`, `participant_high uuid FK`, unique `(participant_low, participant_high)` với ordering theo UUID đã canonicalize; `source_note_id uuid FK ON DELETE SET NULL` hoặc soft-delete reference, `status text`, `last_sender_id uuid NULL`, `streak_count smallint 0..3`, `created_at`, `updated_at`, `closed_at`.
- `last_sender_id` phải thuộc participant set. Không có các conversation bừa bãi từ client chọn user ID.

### 6.5 `messages`

- `id uuid PK`, `conversation_id uuid FK`, `sender_id uuid FK`, `body text`, `created_at`, `client_request_id uuid`, `moderation_status text`, `deleted_at nullable`; unique `(sender_id,client_request_id)`; index `(conversation_id,created_at,id)`.
- Không render message `moderation_status=hidden` cho người dùng ngoài người gửi (gửi có thể thấy trạng thái bị ẩn sau khi review theo policy). Soft-delete & moderation khác nhau.

### 6.6 `blocks`

- `blocker_id uuid`, `blocked_id uuid`, `created_at`, composite PK `(blocker_id,blocked_id)`, check blocker != blocked, index `blocked_id`; read owner/admin only. Có thể duplicate đối xứng; hàm `is_blocked_between(a,b)` kiểm tra cả hai hướng.

### 6.7 `reports`

- `id uuid PK`, `reporter_id uuid`, `target_type note|message|conversation|user`, `target_id uuid`, `reason text`, `description text <=500`, `status pending|reviewing|resolved|dismissed`, `moderator_id uuid NULL`, `created_at`, `resolved_at`; separate `report_evidence` controlled storage với TTL theo policy khi cần chụp snapshot đã báo cáo.

### 6.8 `notifications`

- `id uuid PK`, `recipient_id uuid`, `kind encouragement|message|moderation|system`, `ref_type`, `ref_id`, `created_at`, `read_at`, `delivery_status`; không đưa nội dung nhạy cảm vào push preview mặc định. Index `(recipient_id,created_at DESC)`.

### 6.9 Hạ tầng phụ bắt buộc

- `wall_regions(tile_x,tile_y,published_count,free_count,unencouraged_count,recent_count,last_featured_at,updated_at)` là cache có thể rebuild.
- `daily_note_creations(user_id,day_vn,note_id,created_at)` ledger chống xóa để tạo lại.
- `admin_audit_logs(actor_admin_id,action,target_type,target_id,reason,created_at,request_id)` append-only.
- `user_devices(user_id,device_key_hash,push_token,platform,created_at,updated_at)`; app chỉ đăng ký sau khi user opt in và OS đã cấp quyền. Client không đọc token của device khác; token chỉ được ghi/xóa qua RPC.
- `app_private.push_delivery_outbox(notification_id,device_id,status,attempt_count,available_at,locked_until,sent_at,last_error_code)` là hàng đợi server-only, unique theo notification/device; service-role worker claim bằng `SKIP LOCKED`, retry có backoff và xóa device token khi FCM trả `UNREGISTERED`. Push là at-least-once; thông báo đã được worker claim và đang gửi không thể thu hồi khi user tắt push.
- `request_idempotency(actor_id,operation,request_id,response_code,response_body_hash/result_ref,created_at,expires_at)` hoặc constraints riêng theo operation; tránh dữ liệu nhạy cảm trong bản cache.

---

## 7. API / RPC contract

**Nguyên tắc:** App gọi Laravel HTTPS JSON API với Sanctum bearer token và typed responses. Backend lấy actor từ token đã xác thực, **không tin `sender_id`, `author_id`, `recipient_id` do client gửi**. Không mở direct table reads cho `notes`/`profiles` của người khác. Chỉ expose API operations trả whitelist DTO; transaction place/send nằm trọn trong backend service. Schema truy cập qua Laravel migrations; MySQL credentials chỉ ở server.

### Read endpoints

1. `get_discovery_target(exclude_regions?: [{tile_x,tile_y}])` → `{tile_x,tile_y,camera_world_x,camera_world_y,available_cells_estimate}`. Return region có note, còn chỗ, không expose user data.
2. `get_wall_tiles(min_cell_x,max_cell_x,min_cell_y,max_cell_y,cursor?,limit=200)` → `{items:[{id,cell_x,cell_y,paper_color,style_seed,published_at}],next_cursor,revision}`. Validate viewport area/max items; limit hard max 300; server ignores excessive bounds, rejects with `INVALID_VIEWPORT`.
3. `get_note_detail(note_id)` → `{id,content,paper_color,published_at,can_encourage,can_start_chat,is_owner,allow_chat,can_edit,can_delete}`. No author_id.
4. `get_my_notes(cursor?,limit=20)` → own note list with status, coords, allowed actions.
5. `get_inbox(kind,cursor?,limit=20)` → private own encouragement summary or conversations, no other side identity.
6. `get_messages(conversation_id,before_cursor?,limit=30)` → only for participant, paginate stable `(created_at,id)`; return sender role as `is_mine: boolean`, **not** raw counterpart `sender_id`.
7. `get_account_settings()` → own settings/consents.

### Write endpoints

8. `place_note(content,paper_color,allow_chat,cell_x,cell_y,client_request_id)` → `{note_id,status,cell_x,cell_y,published_at?}`; error `DAILY_LIMIT|SLOT_OCCUPIED|NEEDS_REVIEW|CONTENT_REJECTED|SUSPENDED|RATE_LIMITED`. `NEEDS_REVIEW` may be a successful pending state instead of error; response must be consistent.
9. `edit_note(note_id,new_content)` → allowed only window/rules; returns `{id,status,content_version}`.
10. `delete_note(note_id)` → `{deleted:true}`; idempotent for owner.
11. `update_note_chat(note_id,allow_chat)` → `{allow_chat}`; only owner.
12. `suggest_placement_regions(near_cell_x,near_cell_y)` → list of region centers and <=3 vacant suggestions, server rechecks on final submit.
13. `send_encouragement(note_id,template_key,client_request_id)` → `{id,created_at}` or idempotent existing record.
14. `start_conversation_from_note(note_id,client_request_id)` → `{conversation_id,created,can_send,remaining_outbound}`; no user pair IDs. Starting conversation must not notify author until first message.
15. `send_message(conversation_id,body,client_request_id)` → `{message_id,created_at,remaining_outbound}`; error `MESSAGE_LIMIT_REACHED|BLOCKED|CLOSED|NOT_PARTICIPANT|RATE_LIMITED`.
16. `close_conversation(conversation_id)` → `{status}`. Only participant; for reopening require explicit agreement / not in MVP; may use block flow instead.
17. `report_content(target_type,target_id,reason,description?)` → `{report_id,status}` for a note, message, or conversation.
18. `report_user_from_note(note_id,reason,description?)` / `report_user_from_conversation(conversation_id,reason,description?)` → `{report_id,status}`; the server resolves the other user from the supplied context. The client never submits or receives that user's ID. Their report-and-block variants resolve the same user and block in one transaction.
19. `block_from_note(note_id)` / `block_from_conversation(conversation_id)` / `unblock_from_my_list(block_ref)` → result, no public target user ID.
20. `mark_notification_read(notification_id)`, `update_settings(...)`, `request_account_deletion()`.
21. Moderator-only `review_report(report_id,action,reason)` supports `suspend_user` only for a user-target report; account suspension, token cleanup, report resolution, and audit are atomic.
22. `register_device(device_key_hash,push_token,platform)` chỉ hoạt động khi preference notifications đang bật; `unregister_device(device_key_hash)` xóa token của device hiện tại.

### Error envelope (unified)

```json
{"error":{"code":"SLOT_OCCUPIED","message":"Vị trí này vừa có một tờ giấy khác.","retryable":true,"details":{"suggested_cells":[{"x":12,"y":8}]}}}
```

No sensitive internal errors. HTTP mapping: 400 validation, 401 auth, 403 forbidden, 404 not found/no information leak, 409 collision/idempotency conflict, 429 throttling, 500 unexpected. Realtime events are **signals**; clients fetch canonical records via read endpoints.

---

## 8. Authorization, privacy, security, moderation

### 8.1 RLS policy matrix

| Entity | User read | User write | Admin |
|---|---|---|---|
| `profiles` | own only | own limited fields; status by admin | controlled |
| `notes` raw | owner only where permitted | via validated RPC only | moderation |
| `wall_public_notes` projection | authenticated published metadata only | none | n/a |
| `encouragements` | sender's own; recipient via inbox RPC without sender_id | via RPC | moderation |
| `conversations` | participants only, **no public pair IDs** in DTO | via RPC | moderation |
| `messages` | participants only | via RPC | moderation |
| `blocks` | own | via RPC | controlled |
| `reports` | own report state only | via RPC | review |
| `notifications` | recipient only | mark read own | controlled |

**Security invariants:** `author_id` never exposed from note API; `profiles` unrelated can't be selected; actor identity server-derived; rate limiting by actor/device/IP where legally appropriate; audit admin; storage encryption in transit/at rest per provider, no claim E2EE. `SECURITY DEFINER` risks elevated privileges—use non-exposed schema, limited EXECUTE grants, pinned search_path, fully qualified tables, thorough tests. Supabase documentation explicitly warns about security-definer exposure and RLS bypass.

### 8.2 Content safety & privacy

- Terms of use + community rules accepted before posting. Age gate >=18; appeal/contact route visible.
- Filtering on note **and** message content: obvious spam, threats, targeted harassment, dangerous material, personal data exposure, sexual exploitation, suspected underage content; use moderation provider or controlled heuristics plus human review queue, without claiming 100% coverage.
- Content with serious immediate safety concerns: avoid amplifying publicly, route to moderation, show supportive resources/context-specific emergency advice; explain app is **not** therapy/emergency hotline.
- Admin actions `hide note`, `suspend user`, `close conversation`, `resolve report`, `remove message`; log reason, actor and timestamp, allow appeal/contact; protect staff access and sensitive data.
- Reporting a user from a note or conversation uses that context ID; the server resolves the other user's identity and never returns it to the reporting client or report queue DTO.
- Data deletion: immediate public unpublish and access revocation, background erasure/anonymization subject to documented retention/legal obligations; purge push tokens and caches. Explicit app account deletion flow; no indefinite retention promises.
- No analytics raw text, no token/email/phone in error logs or push payloads. No third-party ad trackers in MVP. Device location permission unnecessary.
- Notification preview neutral: `Có một lời nhắn mới trong Tường Nhỏ`, no private message text on lockscreen.

### 8.3 Legal and store review gate (not legal advice)

Before production, obtain review of applicability of **Vietnam Decree 147/2024/NĐ-CP**, **Personal Data Protection Law 91/2025/QH15** and **Decree 356/2025/NĐ-CP**, including social-network obligations, account verification requirements, cross-border data transfer, consent, and hosting/retention responsibilities. Apple Guideline 1.2 and Google Play UGC rules require filtering/reporting/blocking and ongoing moderation. Apple warns apps used primarily for random/anonymous chat can be rejected; positioning and **real product behavior** must remain a moderated, journaling-first service, not a random chat app. Do not treat description alone as a workaround.

---

## 9. Flutter/Flame implementation details

### 9.1 Main widgets & components

- Flutter: `MaterialApp.router` with themed custom widgets. Feature-first folders `auth,wall,notes,encouragements,chat,inbox,safety,settings` each `domain/data/application/presentation` as needed.
- Flame: `WallGame`, `World`, `CameraComponent`, `TileManager`, `NoteSpriteComponent`, `WindController`, `PaperSelectionOverlay`, `WallGestureController`.
- Riverpod providers: authSession, discoveryTarget, wallTileCache, selectedNote, noteDraft, placementState, inboxUnreadCounts, conversation, settings.
- `GoRouter`: `/welcome`, `/wall`, `/note/:id`, `/compose`, `/place`, `/inbox`, `/chat/:id`, `/me`, `/settings`, `/report`.
- UI opened note should be Flutter overlay receiving a *snapshot* note ID+world rect converted to screen rect; don't instantiate a giant Flutter widget for every note.

### 9.2 Gesture arbitration

- One finger drag starting on empty area → pan camera; tap on note (movement below slop) → open; dragging a note is enabled **only** in Placement Mode. Two fingers → zoom around gesture centroid while preserving world point under fingers; double tap optional (not required MVP). Interaction precedence `modal > placement drag > pinch > wall pan > tap`.
- Guard quick tap, momentum stopping when modal opens, OS back gesture, zoom boundaries, route changes; no accidental post. Safe area & app bottom nav account for viewport.

### 9.3 Quality and performance targets (test goals)

- Median 60 FPS target for pan/zoom on representative Android midrange; monitor p95 raster/build frame time, not only average FPS. Graceful degradation in battery saver/reduced motion.
- Warm tile latency <500ms under typical good network as goal, verify measurements; no blocking pan when network stalls.
- Simulate world with 10,000–100,000 note records, but only tens/hundreds of NoteSprites loaded depending on zoom/LOD; measure frame times and memory after 10 minutes pan/zoom.
- App resumes gracefully; stale subscriptions removed; no duplicate stream listeners; rapid input no crash.

---

## 10. Notifications, analytics, operations

- Only transactional notifications: `encouragement_received`, `new_message` (may coalesce), `moderation_action`, `account_warning`; opted out push must still have inbox.
- FCM/APNs integration; token register after explicit in-app opt-in and OS permission; never require push permission to use app. Database delivery is idempotent by notification/device and cleans invalid tokens. Provider delivery is at-least-once, so collapse duplicate pending alerts and keep the inbox as canonical history; do not claim exactly-once delivery.
- Push previews are fixed neutral text and never contain note/message text, account IDs, conversation IDs, email, or token. The current DB generates encouragement/message notifications; moderation/account-warning notification copy and policy must be approved before wiring those events.
- Privacy-respecting product events: `app_opened`, `wall_region_visited`, `note_opened`, `note_created`, `note_placed`, `encouragement_sent`, `conversation_started`, `message_sent`, `report_submitted`. Allow-list event names, send no event properties or user ID, and keep collection off until provider/disclosure approval. Minimize granularity and retention. **Do not record note or chat content** in analytics.
- KPI definitions: `notes_with_>=1_encouragement_24h / eligible_published_notes_24h`; `D7 retention`; `per-note open→encouragement conversion`; `report rate`; `median report handling time`; `message reply rate`.
- Beta target 70% notes with at least one encouragement in 24h is an **experiment objective**, not promise to users.
- Ops: crash reporting, SQL slow queries, Supabase budget alerts, daily backup availability/restore drills for production, service status page/contact address, incident log, moderation SLA internally defined.

---

## 11. Engineering tests — bắt buộc

### Unit

- `floorDiv` cho negative coordinates; world/screen transforms; tile bounds edge cases; deterministic style seed; input normalization; text length; age fade; chat UI quota states; reduced motion.

### Integration / SQL

1. A và B cùng dán 1 cell đồng thời → đúng 1 thành công; không có duplicate, bên thua nhận `SLOT_OCCUPIED`.
2. Gửi lại request `place_note` cùng `client_request_id` → một note duy nhất và quota 1/day không trừ hai lần.
3. A tạo note, xóa, tạo note lần 2 cùng ngày VN → `DAILY_LIMIT`.
4. A gửi B 3 tin; tin thứ tư bị từ chối; B gửi 1; A gửi được lại; hai yêu cầu song song không vượt streak.
5. A mở chat từ note khác của B → conversation cũ, quota giữ nguyên.
6. C không thể đọc conversation của A-B; A không thể đọc `profiles` của B bằng public API.
7. Public tile API **không có author_id/content**; detail published mới có content; hidden/deleted không đọc được.
8. Block giữa A/B → hai chiều không nhắn/động viên; report quyền đúng actor.
9. Tắt chat trên note → không mở chat mới từ note; conversation cũ vẫn hoạt động cho đến khi đóng/chặn theo rule.
10. Sửa note sau >30 phút hoặc đã có engagement → reject; sửa hợp lệ đi qua kiểm duyệt.
11. Message client retry không duplicate và không tăng streak hai lần.
12. Moderator thao tác phải tạo audit log; user không thể gọi moderator endpoint.

### E2E mobile

- Install → sign in → onboard → xuất hiện ở góc có note → pan/zoom → mở note → động viên → quay lại → viết note → chọn chỗ trống → thành công → tìm lại note → chat test với account B → report/block → logout/delete account.
- Airplane mode during placement; app background during upload; 2 devices simultaneous placement; font scaling 200%; TalkBack; gesture conflict; notification permission denied; account suspended.

### Definition of done chung

Feature chỉ hoàn thành nếu: UX theo spec; validation cả client/server; RLS/security tests; loading/empty/error states; accessibility cơ bản; unit/integration tests phù hợp; tài liệu cập nhật; chạy trên điện thoại thật; không thêm dependency thừa; AI nêu rõ chưa kiểm chứng gì.

---

## 12. Release gates

**Gate A — World POC:** gesture pan/zoom chuẩn, <target frame-time> trên Android thực tế, không leak memory sau 10 phút test; opening animation mượt, reduce motion.

**Gate B — Shared world:** 2 thiết bị nhìn cùng note/cell; đặt giấy cùng vị trí có race protection; note vừa dán hiện sau refresh/realtime tile event; chỉ load vùng nhìn.

**Gate C — Core engagement:** encouragement idempotent; 3-message backend rule chuẩn; inbox/private realtime hoạt động; blocked user không thể gửi.

**Gate D — Safety closed beta:** Auth, terms, reports, blocks, moderation console, account deletion, privacy, crash logs, operational playbook, reviewed legal/store obligations. Không mời public beta trước Gate D.

**Gate E — Production review:** beta metrics & abuse assessment, data protection assessment, accessibility, backups+restore, incident response, store metadata, legal approvals as applicable.

---

## 13. Repo chuẩn

```text
tuong_nho/
  app/
    lib/
      app.dart
      main.dart
      core/{router,theme,config,security,errors}/
      features/
        auth/{domain,data,application,presentation}/
        wall/{domain,data,application,presentation,game}/
        notes/{domain,data,application,presentation}/
        encouragements/{domain,data,application,presentation}/
        chat/{domain,data,application,presentation}/
        inbox/{domain,data,application,presentation}/
        safety/{domain,data,application,presentation}/
        settings/{domain,data,application,presentation}/
      shared/{widgets,models}/
    assets/{paper,pins,decorations,fonts}/
    test/
    integration_test/
  supabase/{migrations,functions,tests,seed.sql}/
  admin/                 # Optional: minimal gated dashboard, introduced at Gate D
  docs/{MASTER_SPEC.md,API.md,DB.md,ADR/,RUNBOOK.md}/
  .github/workflows/
  README.md
```

`pubspec.lock` committed for app; versions pinned and chosen at implementation time from latest compatible stable releases; AI must note versions selected and changelog issues rather than guessing APIs.

---

## 14. AI engineering contract

1. **Read this entire spec before coding.** Implement one milestone at a time. Default to mock repository/seed data until relevant backend milestone.
2. Each task: output `assumptions`, `files changed`, `migration` (if applicable), `tests`, `manual QA`, `known limitations`. Keep changes small and reviewable.
3. Do **not** use Flutter list/feed as replacement for Flame world, nor convert shared world into user-specific random layout.
4. Do **not** expose author IDs, use public nickname, enable free-text encouragement or remove chat limits.
5. Do **not** store keys in git, fake passing tests, invent API signatures or skip device test; disclose unavailable environments.
6. All DB changes via migration + test; never edit production schema ad hoc. No silent schema changes inconsistent with this document.
7. For concurrency-critical RPCs, provide explicit transactional SQL and concurrent test. For privacy-critical endpoints, provide least-privilege grants/RLS and negative tests.
8. If a legal/regulatory issue cannot be resolved through code, flag as `BLOCKER: LEGAL_REVIEW`, do not silently ship.
9. Pixel-perfect visuals are secondary to correct UX and perf; nevertheless no generic Material card grid replacing chibi wall design.
10. End milestone with acceptance checklist PASS/FAIL plus concrete screenshots or recorded artifacts when possible.

---

## 15. Phụ lục: lỗi chuẩn & empty states

| Code | Behavior UI |
|---|---|
| `UNAUTHENTICATED` | điều hướng login, giữ local note draft |
| `UNDERAGE_OR_NOT_ELIGIBLE` | giải thích điều kiện sử dụng, không cho tham gia |
| `SUSPENDED` | thông báo trạng thái + kênh liên hệ |
| `DAILY_LIMIT` | `Hôm nay bạn đã dán một tờ giấy rồi. Hẹn bạn ngày mai nhé.` |
| `SLOT_OCCUPIED` | giữ draft, hiển thị 3 ô trống gần đó |
| `INVALID_VIEWPORT` | reset viewport request an toàn, không crash |
| `CONTENT_REJECTED` | giải thích chung và hướng dẫn chỉnh sửa, không lộ bộ lọc |
| `NEEDS_REVIEW` | note chưa công khai, status pending |
| `NOTE_NOT_FOUND` | `Tờ giấy này không còn ở đây nữa.` |
| `CHAT_DISABLED` | `Người viết chưa mở lời nhắn cho tờ giấy này.` |
| `MESSAGE_LIMIT_REACHED` | disable send, hiển thị đang chờ trả lời |
| `BLOCKED`/`CLOSED` | không cho gửi thêm, không lộ lý do quá chi tiết |
| `RATE_LIMITED` | thông báo thử lại sau, không spam auto retry |
| `NETWORK_ERROR` | cache note draft, retry có kiểm soát, không khẳng định đã đăng |

---

## 16. Tham khảo công nghệ/chính sách (kiểm tra ngày 2026-10-23)

- Flame camera/world: https://docs.flame-engine.org/latest/flame/camera.html
- Supabase RLS & security definer safety: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Realtime Broadcast: https://supabase.com/docs/guides/realtime/subscribing-to-database-changes
- Supabase Pricing: https://supabase.com/pricing
- Apple App Review Guidelines §1.2: https://developer.apple.com/app-store/review/guidelines/
- Google Play user-generated content policy: https://support.google.com/googleplay/android-developer/answer/9876937
- Nghị định 147/2024/NĐ-CP: https://vanban.chinhphu.vn/?classid=0&docid=211654&pageid=27160
- Luật 91/2025/QH15 (hiệu lực 2026-01-01): https://vanban.chinhphu.vn/?classid=1&docid=214590&pageid=27160&typegroup=
- Nghị định 356/2025/NĐ-CP: https://vanban.chinhphu.vn/?classid=1&docid=216387&orggroupid=2&pageid=27160

**End of Master Spec v1.0.0**


---

# D — UX AND MOTION

SOURCE FILE: `docs/03_UX_AND_MOTION.md`

# 03 — UX, visual behavior & motion specification

> Applies to **portrait mobile Android & iOS**. Not a desktop landing page. Baseline is `01_MASTER_PRODUCT_TECH_SPEC.md`.

## Design intent
A gentle, tactile **miniature storybook/chibi environment**, not a grid of glossy Material cards. Entire primary screen is the **edge-less shared wall surface**, not a cork board constrained by a visible wooden frame. Do NOT show an infinite downward list or a fixed number of slots. Users move camera across the 2D world in X/Y; note positions are stable between users.

### Tokens (beta defaults; centralize in `core/theme`)
| Token | Value |
|---|---|
| canvas | `#F3E8D7`, warm creamy wall with subtle non-distracting repeating noise |
| text primary | `#55483E`, secondary `#82756A` |
| paper pink | `#F4D5D8` |
| paper butter | `#F8E5B2` |
| paper sage | `#DCE7D6` |
| paper blue | `#DAE6F1` |
| paper lilac | `#E9E0F3` |
| accent | `#977E70`, warm dark neutral |
| border | hand-drawn appearance only on paper, no strong rectangular outline |
| shadows | diffuse, small and physically plausible; no glassmorphism |
| corner radius | paper minimal/irregular, dialogs comfortably rounded |
| tap target | min 44×44 dp equivalent for accessible interactive controls |

Typography: readable Vietnamese font with Latin extended/Vietnamese diacritics, content line height ~1.5; decorative handwriting only on tiny non-readable preview or headings, never on important body text if contrast suffers. Include font licensing check in asset manifest. Maintain text scaling. Use small cozy decorative cat/flower/leaf illustrations sparingly **outside note tap targets**; keep the content central.

## Navigation
- Auth + privacy onboarding → Wall (`/wall`). Bottom nav `Tường | Hộp thư | Của tôi` (can overlay as compact paper-like dock; must not cover important wall gestures).
- Floating `+` CTA goes to composer then placement mode. In wall HUD: `Đến góc khác`, `Đến note của tôi` where relevant, optional recenter/zoom reset.
- Reader opens from tapped paper as an overlay or route with coordinated hero/FLIP transition; close returns to EXACT prior wall viewport, including scale & center.
- Never show public author display name/avatar, “views”, “likes” or comments.

## Screens / states

### S00 Bootstrap/auth
- Unknown session → splash, then Welcome/Sign In. Authenticated but not consented/age-declared → onboarding; suspended → explain and support route; authenticated ready → Wall.
- Email one-time code (or link) via Supabase Auth; deep link handling if links chosen. Show retry cooldown and network errors. Confirm 18+, rules, terms/privacy before entry; gate is declaration, NOT identity verification promise.

### S03 Shared infinite wall
- Screen mostly wall, paper notes from server: typical 10–25 small papers in normal viewport, but responsive to actual screen/zoom.
- Paper front shows 2–4 fake ink-like lines / doodles determined from `style_seed`; **real content text not rendered on tiny paper** (no content fetched for tile).
- Different deterministic tiny rotations, pin/tape assets, slight local shadow. No same periodic wobble for all papers.
- Gestures: one finger on blank wall pans; pinch zooms at gesture centroid, preserving point under fingers. Tap paper opens, movement slop prevents accidental opens. In browsing, dragging a note doesn't move it.
- Welcome to region with real published notes. Wall may be empty at first service launch; show empty-state with CTA to post, not fake members/messages.
- Loading a new tile should not block pan; use unobtrusive placeholders that don't look like posted notes. Network errors allow cached nearby paper while clearly labeling stale or offline.
- `Đến góc khác` animates/recenters to server-provided discovery tile, no rearranging existing papers. Don't move the camera unexpectedly while reading/placing.

### S04 Reader
- Tap gives tiny lift → eased translation/scale to a larger physical-looking paper with dimmed but visible wall behind. Maintain a single interactive layer and stable back navigation.
- Show full text; content may scroll within reader, respecting larger fonts. Footer: approximate publication time and two CTAs **Động viên / Nhắn tin** for other's note; for own note replace with **Sửa** (if allowed), **Xóa**, **Bật/tắt nhận tin nhắn**.
- Chat disabled → `Nhắn tin` unavailable with neutral explanation. Note removed before open → show `Tờ giấy này không còn ở đây nữa.` and allow close.
- On returning to wall, focus stays at exact previous position. Animation reduced to simple fade for reduced motion users.

### S05 Composer
- `Tâm sự của bạn` max 1,000 grapheme clusters and 6 KiB UTF-8 server cap; show counter, whitespace trim, 5 paper colors, allow-chat default on (toggled explicitly). No image/audio/link attachment.
- Distinguish unsaved draft, composing, placement preview, pending moderation and published. Local draft persists through navigation/app pause (secure local state); clear after successful submit (or explicit discard), not after failed network call.
- Content is public to signed-in adults once published. Show one-line disclosure before choosing location, without constant friction.

### S06 Placement
- On choosing `Tìm nơi dán`, move to near-current area with space or suggest a reachable populated tile with free cells. Display ONE ghost paper on wall; user drags it over slots.
- Snap nearest invisible 180×180 cell. Valid region shows subtle pin marker, occupied shows muted dashed outline. Never draw giant visible grid on released UI.
- Confirmation `Dán tại đây`; show saving state. While submission in-flight, prevent repeated taps but maintain idempotency key.
- `SLOT_OCCUPIED` keeps draft, displays three suggested nearby cells; must ask before moving to any alternative. `DAILY_LIMIT` should not delete draft.
- Publishing yields a soft *pin & flutter* animation, then show paper on global coordinate. Pending review yields private pending status, **not a public paper**.

### S07 Encouragement
- Popover or paper dialog of 5 approved phrases, choose one, `Gửi động viên`. One sender/note maximum; no free-text encouragement MVP. Success returns to reader or inbox; does not expose sender identity to note owner.

### S08 Inbox
- Two tabs: `Lời động viên`, `Tin nhắn`. Each item only shows enough to navigate: note excerpt title controlled safely, template text, time or chat snippet where authorized. No public counterpart ID/avatar.
- Empty copy empathetic, no FOMO. Private unread indicators. Pagination on scroll. Notification permission optional.

### S09 Chat
- 1:1 conversation from a note, own/right vs other/left bubble. Context strip shows the opening note, with safe text only if accessible.
- Banner `Bạn còn 2/3 tin nhắn trước khi người ấy phản hồi`, computed from **server returned state**, not only local count; at 3/3 disable send with explanation.
- `Đóng trò chuyện`, `Chặn`, `Báo cáo` accessible. No typing indicator, read receipts, public identities, images, voice or links in MVP.
- Chat keyboard safe-area, retry idempotency, reconnect fetch missing messages, no optimistic fourth message.

### S10 My Notes / S11 Settings / S12 Safety
- My Notes includes statuses `Đã dán`, `Đang kiểm tra`, `Đã ẩn`, `Đã xóa`; jump to a published note's fixed global coordinates, edit if allowed, delete.
- Settings: privacy explanation, reduced motion, notifications, community rules, legal policies, account deletion and logout.
- Report/Block surfaced from note and chat; report reason, optional 500-character explanation, clear confirmation; cannot reveal hidden author identity.

## Motion specification
- Pin anchor at top center; tiny free bottom-edge flutter based on seeded independent phase: cycle 3–7s, angular displacement roughly ±1–2 degrees; may add subtle asymmetric bottom-corner deformation IF cheap, but should degrade gracefully.
- Entry to reader: target duration ~280–420ms with spring/ease-out and no sharp overshoot. Closing reverses. Pin/place: ~300–550ms with a short settle. All timings are design defaults to tune on device.
- Paused/reduced motion: `MediaQuery.disableAnimations` or platform accessibility signal → no perpetual paper motion, simple fade reader transition, no parallax.
- LOD: at distant zoom, use colored rectangles/dots only; at normal zoom sprite paper/tape; only near zoom animate edges/doodles. Scale physical hit target thoughtfully.

## Explicit visual reject criteria
- A dashboard/card grid, carousel of bulletin boards, vertical feed of note cards, heavy wooden border that ends at screen edge, neon gradients, glassmorphic panels, identical wobble on all papers, illegible full-reader text or font without Vietnamese glyphs.


---

# E — API CONTRACTS

SOURCE FILE: `docs/04_API_CONTRACT.md`

# 04 — API contract for mobile/backend

All operations below are **logical API contracts**, not guarantees of a specific Supabase-generated HTTP status. Agent chooses typed Dart repositories over network transport and normalizes PostgREST/RPC/Edge errors into `ApiResult<T>`. Server derives user ID from verified auth context. `author_id`, `sender_id`, `recipient_id` are NEVER accepted in client requests.

## Envelope
Success: `{"data": { ... }, "request_id":"uuid-optional"}` at application-layer adapter. Error: `{"error":{"code":"SLOT_OCCUPIED","message":"Chỗ này vừa có tờ giấy khác.","retryable":true,"details":{...}}}`. For RPC returning raw rows, normalize in Dart repository; do not assume Supabase RPC automatically returns this envelope.

Use cursor paging, deterministic `(created_at,id)` or `(cell_y,cell_x,id)` depending query. All timestamps RFC3339 UTC, all display times localized. Auth required for every user-data operation.

## Reads
| Operation | Input | Allowed output (minimal) | Notes |
|---|---|---|---|
| `get_discovery_target` | up to 10 recent tile keys | `tile_x, tile_y, camera_world_x, camera_world_y` | Only eligible tiles with real published notes. |
| `get_wall_tiles` | `min_cell_x,max_cell_x,min_cell_y,max_cell_y,cursor?,limit<=200` | `items[{id,cell_x,cell_y,paper_color,style_seed,published_at}],next_cursor,revision` | 32×32 cell rectangular max per request; larger views use LOD/density endpoint. **NO CONTENT OR AUTHOR**. |
| `get_wall_density` | coarse tile bounds / zoom bucket | `[{tile_x,tile_y,published_count}]` | Aggregate only when too zoomed out; no identifiable note data. |
| `get_note_detail` | note ID | `id,content,paper_color,published_at,is_owner,can_encourage,can_start_chat,can_edit,can_delete` | No `author_id`. Removed/hidden other people's note returns not found. |
| `get_my_notes` | cursor,limit<=30 | own list of id,content,status,coords,created_at,allow_chat | Owner only. |
| `get_inbox` | kind `encouragements|chats`,cursor,limit<=30 | safe summarized items, unread state | No sender public ID. |
| `get_messages` | conversation UUID,before_cursor,limit<=50 | `items[{id,body,is_mine,created_at,status}],remaining_outbound,next_cursor` | Only participant. |
| `get_my_settings` | none | adult/consent/settings flags | Self only. |

## Mutations
| Operation | Input | Result | Core checks |
|---|---|---|---|
| `place_note` | `content,paper_color,allow_chat,cell_x,cell_y,client_request_id` | `note_id,status,cell_x,cell_y` | one/day Vietnam, active-cell unique, moderation, retry safe |
| `edit_note` | `note_id,new_content,client_request_id` | `note_id,content_version,status` | owner, 30 min since creation, NO interactions, re-review |
| `delete_note` | `note_id,client_request_id` | `deleted:true` | owner; public unpublish immediately; quota remains used |
| `update_note_chat` | `note_id,allow_chat` | `allow_chat` | owner; only prevents new conversations from note |
| `suggest_placement_regions` | `near_cell_x,near_cell_y` | list of eligible regions and suggestions | suggestions never reserve slot |
| `send_encouragement` | `note_id,template_key,client_request_id` | `id,created_at` | valid template; no owner; one sender/note; not blocked |
| `start_conversation_from_note` | `note_id,client_request_id` | `conversation_id,remaining_outbound,created` | note permits chat; no arbitrary recipient identity; existing pair reused |
| `send_message` | `conversation_id,body,client_request_id` | `message_id,created_at,remaining_outbound` | participant, 3 consecutive, block check, moderation, atomic |
| `close_conversation` | conversation ID | status | participant, irreversible closure in MVP |
| `block_from_note` / `block_from_conversation` | target note or conversation ID | success | maps counterpart server-side; no identity leak |
| `report_content` | target type+ID, reason, optional description | report ID/status | validate target is accessible, rate limit |
| `mark_notification_read` | notification ID | success | recipient only |
| `request_account_deletion` | confirmation + idempotency ID | deletion request status | immediate public hide/access revocation |

## Example: camera tile fetch
Request:
```json
{"min_cell_x":-16,"max_cell_x":15,"min_cell_y":-8,"max_cell_y":23,"limit":200}
```
Response:
```json
{"data":{"items":[{"id":"5f8d6e76-4b14-4c6c-9c5e-42c2ef7dad11","cell_x":-1,"cell_y":4,"paper_color":"pink","style_seed":1287,"published_at":"2026-10-23T00:00:00Z"}],"next_cursor":null,"revision":"r12"}}
```
Note NO content, user reference, author ID, email or receiver pointer.

## Example: placement
```json
{"content":"Hôm nay mình đã cố gắng nhiều rồi.","paper_color":"sage","allow_chat":true,"cell_x":-1,"cell_y":4,"client_request_id":"e52f1073-30c4-4c9a-b85e-98974b34796d"}
```
- Repeat same actor+request ID returns same result; never uses two daily quotas.
- Conflicting new request to occupied cell yields `SLOT_OCCUPIED`, not auto-move.
- Even if note goes `pending_review`, daily quota is used; policy visible to poster.

## Example: send message
```json
{"conversation_id":"77d834b8-750b-41d4-a9d6-e1c9de603a27","body":"Nếu muốn tâm sự, mình ở đây.","client_request_id":"ac0a54c7-4cca-4d1f-b85e-781224cc0f55"}
```
For a given `(conversation_id, sender_id)`, if streak is `3` and same sender sent last → `MESSAGE_LIMIT_REACHED`. If other party sent last → current sender's streak becomes `1`. Reply from other does NOT allow more than three consecutive messages for anyone.

## Business error codes
`UNAUTHENTICATED`, `NOT_ELIGIBLE`, `SUSPENDED`, `INVALID_INPUT`, `INVALID_VIEWPORT`, `DAILY_LIMIT`, `SLOT_OCCUPIED`, `NOTE_NOT_FOUND`, `EDIT_WINDOW_CLOSED`, `CONTENT_REJECTED`, `NEEDS_REVIEW`, `ALREADY_ENCOURAGED`, `CHAT_DISABLED`, `MESSAGE_LIMIT_REACHED`, `BLOCKED`, `CLOSED`, `NOT_PARTICIPANT`, `RATE_LIMITED`, `NETWORK_ERROR`, `INTERNAL_ERROR`.

Validation defaults: note max 1,000 Unicode grapheme clusters and 6 KiB UTF-8; chat body 1–500 grapheme clusters / 3 KiB UTF-8 (new explicit beta assumption); report optional description <=500 graphemes. Whitespace-only body invalid; normalize Unicode and newlines safely; reject excessive payload. Never accept arbitrary rich HTML into rendered note/chat.

## Realtime
- Subscription authorization for private channel per conversation or recipient: no third parties; server event contains only `kind,id,revision`, not actual message body.
- On realtime event, fetch canonical records using authenticated read API; reconnect sync by cursor. Invalidate region tile when a published note changes; do not stream camera movement/world positions.
- Prevent duplicate notifications by deterministic event id/idempotency.


---

# F — DATABASE / SECURITY

SOURCE FILE: `docs/05_DATABASE_AND_SECURITY.md`

# 05 — Database / atomic behavior / security specification

Canonical field-by-field dictionary is in `01_MASTER_PRODUCT_TECH_SPEC.md` §6; here are constraints and transaction algorithms Codex MUST implement/test. DB remains source of truth; wall tiles are a spatial *projection*, not identities.

## Tables (minimum)
`profiles`, `notes`, `daily_note_creations`, `wall_regions`, `encouragements`, `conversations`, `messages`, `blocks`, `reports`, `notifications`, `user_devices`, `admin_audit_logs`; optional `request_idempotency`, `moderation_events`, `app_settings`. Admin dashboard uses privilege-checked API, never direct shared client-side service-role access.

## World coordinates and placement
- The only canonical position is signed integer `cell_x,cell_y` (`BIGINT`) and constant `CELL_SIZE_WORLD = 180` (not GPS, pixels or per-user positions).
- Note rectangle = 118×145 world units; style offsets ≤6 units and tilt ±5°. Compute style/rotation deterministically from `style_seed` (NOT truly random each visit). Simple bounds guarantee paper does not cover another note's clickable area at default size.
- Tile width = 8 cells, `tile_x = floor(cell_x/8)`. Critical: for negative cells, floor(-1/8)=-1. Implement same floor arithmetic in Dart and PostgreSQL; test -9,-8,-7,-1,0,1,7,8,9.
- Schema index: UNIQUE `(cell_x,cell_y)` for notes with reserved statuses (`pending_review`,`published`,`hidden`) so collisions are DB-enforced, not merely checked by an API. Prefer partial unique index; ensure moderation actions do not accidentally free occupied cell. Deleted notes free coordinates.
- Assign `creation_day_vn = (now() at time zone 'Asia/Ho_Chi_Minh')::date` server-side; ledger unique `(user_id,creation_day_vn)` so deleting cannot bypass one-note-per-day. Do NOT calculate quota day using device timezone.

## Transaction: `place_note`
1. Obtain authenticated actor and eligibility; normalize/validate payload server-side.
2. Check existing `(actor,operation,client_request_id)` first. If prior success exists, return same result; if same ID with different payload, return idempotency conflict. Avoid a `pending` record stuck forever; ensure cleanup/reconciliation.
3. Begin transaction: validate rate limit, insert ledger with unique user/day, insert note with requested cell, enforce active-cell unique; on any failure rollback BOTH ledger and note.
4. Classify post as published or pending review, depending moderation rule; committed result is canonical. Failed placement must not consume quota. Pending review committed DOES consume quota.
5. Update region statistics transactionally or asynchronously with idempotent recomputation; region counters are caches, never source of truth for occupancy.
6. Notify tile viewers by authorized lightweight invalidation only if published.

**Concurrency test:** two independent actors trying same cell concurrently => one accepted, one conflict. Same actor retried identical ID => one logical note. Race between delete/repost same day => limit remains.

## Transaction: `send_message`
1. Authenticate actor. Verify conversation participant, active state, no blocks in either direction, content/rate-limit/moderation policy.
2. Deduplicate actor+client_request_id BEFORE checking streak; return previous accepted message if retried.
3. `SELECT ... FOR UPDATE` conversation row (or equivalent atomic serialization) in a single DB transaction.
4. `new_count = last_sender_id == actor ? streak_count+1 : 1`. Reject if new_count>3. Enforce DB CHECK 0<=streak_count<=3.
5. Insert message; update `last_sender_id`, `streak_count`, `updated_at`; commit atomically. A rejected 4th message creates no message, no notification, no counter change.
6. If content is queued for review, decide precise visible state (pending sender-only vs reject) BEFORE milestone M3. For MVP default **reject clearly disallowed content** and hold uncertain content without delivery or streak charge until accepted in atomic send pipeline. Preserve audit and privacy.
7. Emit private signal and neutral push after commit (idempotently).

**Concurrency test:** sender issues 4 parallel unique requests from devices; at most 3 accepted. A sends 3→A blocked→B sends 1→A sends 3 possible; delete local chat/another note cannot reset streak. A different pair has its own streak.

## Transaction: `start_conversation_from_note`
- Input only note ID. Resolve author internally; reject self, hidden/deleted note, blocked pair, note `allow_chat=false`. Participants canonical `low/high` UUID ordering and unique constraint; use insert-on-conflict returning existing ID. Starting conversation without first message does not alert recipient.
- Pair-level conversation can reveal notes with same author to chat participants when conversation reused. This trade-off must be explained in privacy UX; NEVER claim unlinkability per note.

## Encouragement
- Five server-approved enum/template IDs; one per `(sender_id,note_id)` enforced UNIQUE. Reject own note; block check both directions. Separate from `messages`; does not count as chat reply. Client retry key is deduplicated. Template text resolved to Vietnamese UI from app constant/server catalog; no personal sender identity in author's inbox.

## Ownership & RLS
**Default deny access** to raw tables not needed by end users. Expose functions with explicit whitelisted DTOs and correct auth checks. Ownership matrix:

| Resource | Self | Other normal user | Moderator |
|---|---|---|---|
| Raw `profiles` | own minimal fields | NO | controlled only |
| Raw `notes` including author_id | own via gated repo/RPC | NO | gated moderation |
| Public note tile DTO | yes | yes, authenticated only | yes |
| Public note detail DTO | yes if published/own | yes if published only | yes |
| Encouragement records | own sent or own note inbox view, IDs stripped | NO | audited |
| Conversation/messages | participant | NO | audited case handling |
| Notifications | recipient | NO | admin limited |
| Reports | reporter limited status | NO | review role |
| Admin audit | NO | NO | scoped admin only |

- `SECURITY DEFINER`: use only if needed, restrict `EXECUTE` grants, set `search_path=''` or restricted path, fully qualify references, never expose unguarded privileged methods. Document caller role and return schema. Avoid relying on RLS of underlying table inside privileged function—perform explicit auth checks.
- Admin identity: verified role stored server-side (e.g., `app_metadata` or protected role membership), NEVER `user_metadata` that client can set; audit every privileged action. Separate admin and regular app credentials where feasible.
- Protect realtime channels with authorization policies; no public chat channel.
- Do not return `author_id`, `participant_low/high`, emails, device identifiers, IP, exact personal location from public functions.
- Deny access to adult-unconfirmed/unconsented accounts until eligibility gate. Keep account deletion and moderation records per documented retention/legal policy; no fake promise of instant physical purge from backups.

## Moderation state machine
- Note: `pending_review → published | rejected`; `published → hidden | deleted`; `hidden → published | deleted` by authorized moderation/owner rule; `deleted` terminal. Avoid publishing risky note by default if flagged.
- Message: `pending_review → delivered | rejected`; `delivered → hidden`. If asynchronous message review is used, define and test **whether quota is consumed when finally delivered**, not at pending. Simplest beta path is synchronous validation and review-status response with no member delivery until approved.
- Reports: `pending → reviewing → resolved|dismissed`; all transitions audited.
- Blocking must stop new messages and encouragement regardless of whether one party is already involved in conversation; author identity resolved server-side.

## Data privacy & account deletion
- No public profile; no content in analytics/logs/push payloads. Server's storage region and cross-border data transfer require review before beta.
- In-app account deletion: immediately deny session/write, hide public notes, close/disable chats, revoke push tokens; erase/anonymize per documented retention schedule and any lawful preservation exceptions. Build tests for hide & privacy behavior, verify backup retention claims separately.
- No persistent plain-text cache of private conversations unless encrypted and scoped; cached wall tile metadata is safe to retain short-lived under policy.

## Additional security tests
Test SQL privileges as real `authenticated` sessions A/B/C and `anon`, not as owner/admin bypass. Confirm A cannot call write operations as B by injecting sender/author IDs, cannot enumerate profiles, cannot SELECT hidden notes through direct tables, cannot listen to private B channel, cannot delete B note, cannot reset quota from device tampering.

## Migration policy
- `001_core.sql`: profiles, status enums/constraints, notes, daily ledger, regions, indexes and foundational RLS.
- `002_wall_rpc.sql`: viewport, detail, placement, lifecycle functions.
- `003_engagement.sql`: encouragement, conversations, messages and transactional RPC.
- `004_safety.sql`: block, report, moderation roles/audit, notifications, deletion.
- Migration files are created in code phase; this doc is a contract, NOT executable SQL. Seed must use explicit test accounts/fictional sample content clearly marked; no fake live members in production.


---

# G — TEST ACCEPTANCE

SOURCE FILE: `docs/06_TEST_ACCEPTANCE.md`

# 06 — Acceptance tests & definition of done

All checked items in task list require evidence, not self-reported success. Automated test vs manual/device verification are different; record both in `docs/PROGRESS.md`.

## Feature acceptance (Given / When / Then)

### AC-01 Shared wall is stable
**Given** A and B open overlapping global coordinates, **when** A has posted a published note at (-1,4), **then** B sees the same paper in the same cell and deterministic style; after fresh app restart it remains in place. Different discovery spawn locations MUST NOT permute notes.

### AC-02 Pan/zoom on mobile
**Given** an Android phone, **when** user pans in all 4 directions and pinch-zooms around a point, **then** zoom keeps the world coordinate beneath pinch focal point stable, gestures don't open note accidentally, UI doesn't stall when tile fetch is pending; reduce motion disables perpetual flutter.

### AC-03 Read only upon tap
**Given** wall contains tiny note, **when** user views wall normally, **then** no real content body is downloaded into wall tile DTO; when they tap, reader shows full content, and closing returns exactly to old camera coordinates.

### AC-04 One note per VN calendar day
**Given** a consenting eligible user posted once on calendar day VN, **when** they attempt another, including after deleting first note, **then** server rejects `DAILY_LIMIT`. After midnight Vietnam time server permits one note the next calendar day. Concurrent posts by same user cannot break limit.

### AC-05 Placement race
**Given** users A and B preview same empty cell, **when** they submit concurrently, **then** EXACTLY ONE note reserves it, other receives `SLOT_OCCUPIED`, keeps draft, receives nearby suggestions; server does not move note silently.

### AC-06 Idempotent placement
**Given** A sends same `client_request_id` twice (retry) with same payload, **when** both requests complete, **then** only one note and one daily ledger entry exist, both responses describe the same operation.

### AC-07 No author leak
**Given** B views A's public tile/reader, **when** inspecting DTOs, logs and UI, **then** no author ID, email, public handle, account lookup or device data is available. Server admins still resolve true owner for safety.

### AC-08 Encouragement
**Given** B reads A's note, **when** B sends one predefined encouragement and retries same request, **then** A sees exactly one encouragement; B cannot send another template to same note; no public counts/user profile appear.

### AC-09 Message streak
**Given** A/B pair, **when** A sends 3 messages without reply and attempts 4th, **then** 4th is denied at server. When B sends one, A can send up to 3 more; another note from B does not create another quota. Four parallel A requests accept at most 3.

### AC-10 Block/report
**Given** A blocks B from a note/chat, **when** B tries to send new messages, encouragement or start chat, **then** server denies contact in both directions. Report creates review queue item, without exposing target's account ID.

### AC-11 Owner rights
**Given** B's note, **when** A tries update/delete or read pending/hidden, **then** authorization denies. B can delete own note; tile query stops returning it. Edit only within 30 minutes AND before engagement; content revalidation applies.

### AC-12 Offline, life-cycle
**Given** placement draft while network fails, **when** app goes offline/background and returns, **then** no false success, draft remains, retry uses same idempotency ID; unreadable private messages do not leak to another account after sign-out.

### AC-13 Empty system
**Given** no real notes at all, **when** first eligible user joins, **then** user sees a clear empty-state and may post. App MUST NOT invent fake anonymous posts or fake human responses to fill the wall.

### AC-14 Public launch safety
**Given** owner wants to invite beta users, **when** moderation tooling, reports/blocks, account deletion, policy and incident response are not operable, **then** release gate fails; not publicly open.

## Unit and integration test suite
- Dart: signed floor division; transforms; zoom anchored focal point; tile query bounds; view-model and JSON decoding; disabled button states; deterministic paper style; reduced motion and accessibility.
- SQL: RLS negative tests; unique occupancy; VN calendar/day boundaries; idempotency payload mismatch; pair unique conversation; 3-message race; block; moderation transitions; private inbox and untrusted ID injection.
- Flutter integration: sign in/out, composer, placement, note reader, encouragement, inbox, chat, report, delete, offline/reconnect, large font, TalkBack and notification permission declined.
- Realtime: unauthorized subscriber can't join; reconnect catches missed events; no private body in public signal.

## Performance acceptance
- Test at least one real lower/mid Android model AND emulator; track model/OS, build mode, sample region density, screen resolution, p50/p95 frame timings, memory after 10 minutes camera roaming, 4G-like network throttling. Target ~60fps and no unbounded growth; failures require documented mitigation, not hiding notes.
- 10k–100k notes in TEST database across regions; only near-camera components instantiated. Zoom-out aggregate path avoids fetching unlimited note records.
- Leak tests: open/close paper 50 times, navigate inbox 50 times, repeatedly enter/exit wall; no accumulating subscriptions/overlays.

## Milestone gates
- **G0:** clone -> Flutter project boots, lints and basic tests pass (toolchain ADR written).
- **G1:** Wall POC works offline on Android; gestures, motion, note open, placement mock, tile culling and perf report.
- **G2:** Shared note persistence, auth, protected read DTOs, posting quota, edit/delete, collisions, retries verified on 2 accounts.
- **G3:** Encouragement and chat (streak and private channel) pass SQL + UI flows; inbox private.
- **G4:** Moderation, block, report, consent, account deletion, audit, crash reporting and operational procedures exist; beta QA passes.
- **PRODUCTION:** separate owner authorization, platform policy/legal review, release metadata, backup restore drill, observed beta quality.

## Mandatory Codex task completion format
```
TASK: Mx-y
STATUS: PASS | FAIL | PARTIAL
CHANGED FILES: ...
COMMANDS: [exact commands and exit status]
AUTOMATED TESTS: [passing/not run + reason]
MANUAL QA: [device evidence / pending]
SECURITY REVIEW: [which invariants verified]
BLOCKERS: ...
NEXT: Mx-(y+1)
```
Never say `PASS` for toolchain/device/security evidence you did not observe. An unavailable SDK means `NOT RUN`, not `PASS`.


---

# H — IMPLEMENTATION PLAN

SOURCE FILE: `docs/02_IMPLEMENTATION_PLAN.md`

# TƯỜNG NHỎ — AI IMPLEMENTATION PLAN / MILESTONE BACKLOG

**Nguồn chuẩn:** `01_MASTER_PRODUCT_TECH_SPEC.md`. Nếu xung đột, MASTER SPEC thắng. **Cách làm:** mỗi task một pull request, không code toàn bộ dự án trong một prompt.

## 0. Preconditions

- [ ] Flutter SDK + Android SDK hoạt động; `flutter doctor -v` không có lỗi blocker cho Android.
- [ ] Thiết bị Android thật để profile; iOS chỉ test/build khi có macOS+Xcode.
- [ ] Git repo riêng tư, GitHub Actions; bật secret scanning/dependency audit nếu khả dụng.
- [ ] Supabase project DEV/BETA riêng, không dùng production ngay; Supabase CLI local.
- [ ] Chọn/ghi phiên bản package thực tế vào ADR `ADR-001-toolchain.md`; không đoán version trong prompt.
- [ ] Domain/app identifier và package name tạm thời nhất quán; trước ra mắt kiểm tra tên/thương hiệu.
- [ ] Docs: privacy policy, terms/community guidelines, contact email, SOP moderation và legal review tồn tại trước beta.

### Toolchain commands (examples)

```bash
flutter doctor -v
flutter create --org app.tuongnho tuong_nho
cd tuong_nho
flutter pub add flame flutter_riverpod go_router supabase_flutter
flutter analyze
flutter test
flutter run -d <android-device-id>

# Supabase CLI must be installed separately; pin CLI version and review migrations.
supabase init
supabase start
supabase db reset
supabase test db
```

**Tham số `<...>` là placeholder, không chạy nguyên xi.** Chỉ cài `firebase_messaging`/`firebase_crashlytics` khi tới milestone notification. Không đưa service-role/admin secret vào app.

## M0 — Specification & foundation (tuần 1)

**TASK M0-1** Repo + lint + themes. Đầu ra: `README`, `docs/ADR`, Flutter chạy màn hình placeholder, theme fonts/colors, router, CI job `analyze/test`. PASS: clone mới chạy được, no warnings nghiêm trọng.

**TASK M0-2** Design tokens + asset pipeline. Đầu ra: 5 giấy pastel, 2 loại ghim/băng dính, nền seamless tối ưu, shader/texture nhẹ, license log; fallback placeholder không tốn bộ nhớ. PASS: assets không méo ở các tỷ lệ màn hình, texture tái dùng chứ không upload PNG khổng lồ.

**TASK M0-3** Contract shared models. Tạo freezed/json_serializable nếu thấy cần, hoặc dùng handwritten models tối giản; domain types cho `NoteTile`, `NoteDetail`, `WorldCell`, `WallRegion`, `PlacementResult`, `Conversation`, `Message`. PASS: unit tests serialize/deserialize và invalid models. Không bind trực tiếp row Supabase lên UI.

## M1 — Wall POC offline (tuần 2–4)

**TASK M1-1 Flame world & camera:** World, CameraComponent, pan 4 hướng, pinch anchored focal point, zoom clamp, bounds infinite virtual. PASS trên máy thật: pinch không nhảy, không kéo cả khi nhấn note.

**TASK M1-2 Note component:** 50–100 note seeded deterministic, mỗi giấy 118×145 world units, lưới 180, style seeded, paper flutter lệch pha; animation off khi reduced motion. PASS: chibi nhẹ, mượt, không chồng tap target.

**TASK M1-3 Tap to open:** world→screen rect, Flutter overlay chuyển giấy ra màn hình đọc, backdrop dim, close animation về note; không fetch network. PASS: open/close 30 lần, không leak overlay, back hoạt động.

**TASK M1-4 TileManager & LOD:** chunks 8×8 cell, culling + LRU + mock 10k note, zoomed out clustering, no excessive components. PASS: profile 10 phút, không tăng RAM liên tục, frame time đo trong DevTools và ghi vào `PERF_REPORT.md`.

**TASK M1-5 Placement POC:** ghost paper, snap cell, occupancy preview, confirm/cancel, collision local fake, deterministic transform. PASS: không thể đặt 2 giấy vào cùng ô trong local POC.

**Gate G1:** Demo Android chạy bức tường, có thể khám phá/dán giả lập, 2 sizes màn hình; đính kèm video/screenshot + FPS report. Chưa có Auth/DB.

## M2 — Supabase foundation + real shared wall (tuần 5–8)

**TASK M2-1 Auth and Terms:** email OTP auth, custom SMTP cấu hình DEV/BETA, session, 18+ declaration, terms consent, onboarding, logout. PASS: user không chưa consent không được post.

**TASK M2-2 Schema migration 001:** tables profiles, notes, daily_note_creations, wall_regions; status constraints, keys, indexes; RLS deny by default; protected read projection. PASS: `supabase db reset` clean, SQL tests complete.

**TASK M2-3 Canonical coordinate functions:** floor division số âm; world-to-cell; tile indices; unique active occupancy; allocation suggestion. PASS: cùng tọa độ trên hai client, no overlap; collision server authoritative.

**TASK M2-4 API `get_wall_tiles`, `get_note_detail`, `get_discovery_target`:** minimization DTO (no author_id/content in tiles), viewport limit, pagination. PASS: two devices see same layout, A cannot identify author via public API.

**TASK M2-5 `place_note` transaction:** one-note/day VN regardless delete, idempotency, moderation status, unique cell occupancy, confirmation. PASS: concurrency tests two accounts simultaneous, 2 requests same client ID, quota deletion bypass fails.

**TASK M2-6 Note composer & placement integration:** draft, keyboard, error states; local preview; success/review/error; note own jump. PASS: manual E2E with 2 devices, force-network-off recovery.

**TASK M2-7 `edit_note`/`delete_note`/`update_note_chat`:** server rule 30m/no interaction, tombstone; tile invalidation. PASS: author only; delete removes from public wall.

**Gate G2:** Authenticated users A/B can each dán paper in separate cells, see identical world and published notes, all denied actions tested.

## M3 — Encouragement + chat (tuần 9–12)

**TASK M3-1 Encouragement schema and endpoint:** templates, uniqueness, block checks, idempotency, notice to owner. PASS: owner cannot self-encourage, retry duplicates none, sender identity hidden.

**TASK M3-2 Inbox:** summaries, unread local/store sync, no public sender identity, empty/error/offline states. PASS: encouragement visible after recipient reconnects.

**TASK M3-3 Conversation schema + create:** one pair unique with canonical participant ordering, source note context, caller cannot select recipient ID, no notification until first message. PASS: same pair across 2 notes reused; irrelevant user access denied.

**TASK M3-4 Transactional `send_message`:** count streak lock, membership/block/status, idempotency and rate limit. PASS: 3→block 4th→other side reply→reset; concurrent 4 sends still max 3.

**TASK M3-5 Realtime & push-safe events:** private Broadcast subscribed only for involved parties, token refresh, reconnect fetch delta; wall tile invalidation. PASS: third account denied channel access, no body leaked in public payload.

**TASK M3-6 Conversation UI:** simple bubble chat, character count, 3/3 lock status, sender labels, close/block/report action, keyboard/back/resume. PASS: correct remaining quota after app restart and from 2nd device.

**Gate G3:** A viết note → B động viên/chat → A trả lời → B gửi tiếp, tất cả có test.

## M4 — Safety, operations, closed beta (tuần 13–16+)

**TASK M4-1 Report/block:** report note/message/conversation/user, user block from note/conversation, two-direction enforcement; moderation reasons. PASS: victim can immediately stop new contact.

**TASK M4-2 Moderation pipeline:** filter note/message, flagged/pending/hidden states, queue; no automatic publishing of risky content. PASS: flagged test fixtures held/handled predictably; manual actions audited.

**TASK M4-3 Admin console:** minimal protected web page or internal tool (Next.js optional), role-based audit, report queue, hide/remove/suspend/resolve, contact/support. PASS: normal user cannot access admin pages/RPC.

**TASK M4-4 Account deletion/data retention:** in-app request, revoke tokens, hide public content immediately, purge/anonymize subject to policy, export request handling if legally required. PASS: no public note after delete and no account access.

**TASK M4-5 Observability + notification:** Crashlytics + FCM/APNs, key metrics, budget alerts, DB backup restore rehearsal; do not log contents. PASS: notifications neutral and disabled gracefully if permission denied.

**TASK M4-6 QA/perf/accessibility:** 10k–100k seeded notes DB, simultaneous clients, p95 frame data, text scaling, TalkBack, offline/reconnect, race conditions, battery/reduced motion. PASS: known issues documented and release blockers fixed.

**TASK M4-7 Legal/store readiness:** terms/privacy/support, Vietnam compliance review, age eligibility, store UGC moderation requirements, Apple anonymous chat review risk, release notes, data safety disclosures. PASS: owner signs off release checklist; legal blockers remain blockers.

**Gate G4:** Closed beta invitation with moderation on-call/process and incident reporting. **Không public-launch nếu chưa đáp ứng Gate G4.**

## 5. Issue template để giao AI từng task

```markdown
Task ID: [M1-2]
Context: Đọc 01_MASTER_PRODUCT_TECH_SPEC.md và 02_IMPLEMENTATION_PLAN.md.
Goal: [mục tiêu duy nhất]
Allowed files: [paths cụ thể]
Do not change: [contracts/decisions]
Implementation constraints: [architecture + dependencies]
Acceptance criteria:
- [ ] ...
- [ ] ...
Testing:
- flutter analyze
- flutter test
- supabase test db (nếu có DB)
- device manual QA [steps]
Deliver:
1. Short design
2. Code diff
3. Tests
4. Commands run + results
5. Known limitations
6. Next task suggestion (do not implement)
```

## 6. Risks and mitigations

| Rủi ro | Cách giảm thiểu |
|---|---|
| Agent tự thêm features | Khóa non-goals, issue scope nhỏ, review diff |
| World lag trên máy yếu | POC trước backend, culling/LOD, giảm animation |
| Public author leakage | DTO projection, RPC, RLS negative tests |
| Race condition dán/chat | DB unique+transaction+lock; concurrent tests |
| Feed thưa/không ai đọc | vùng khởi đầu có note; fairness discovery; theo dõi analytics |
| Người dùng bị quấy rối | report/block/moderation trước beta |
| Chi phí Supabase tăng | ít realtime channels, pagination, tiles cache, alerts |
| Không duyệt App Store | thiết kế journaling-first, robust UGC moderation, legal/policy audit |
| Quá nhiều scopes | Non-goals v1, từng gate, trì hoãn admin polish/extra theming |
| Liên kết nhiều note cùng tác giả qua chat | tài liệu trade-off, user-facing privacy explanation, đổi model ở v2 nếu cần |

## 7. Definition of READY to ship

- [ ] Spec, code, migrations, API contracts cùng một phiên bản.
- [ ] Không có P0/P1 security/security-of-identity bugs.
- [ ] All critical SQL concurrency and RLS tests pass.
- [ ] Android E2E pass on at least 2 device classes; iOS QA before iOS launch.
- [ ] No published note without moderation policy; report/block always accessible.
- [ ] Error states/empty states/accessibility/reduced motion tested.
- [ ] Has working support/contact/privacy/terms and account delete.
- [ ] Billing alerts, logging, backups, operational response owner.
- [ ] Store review and Vietnam legal release gates addressed.
- [ ] Closed beta confirmed real-world UX (no fake users/messages).


---

# I — TASK BACKLOG

SOURCE FILE: `tasks/BACKLOG.md`

# TASK BACKLOG — single source for current coding order

**Rule:** complete in order; check only after tests and evidence are logged in `docs/PROGRESS.md`. Full acceptance lives in `docs/02_IMPLEMENTATION_PLAN.md` and `docs/06_TEST_ACCEPTANCE.md`.

Start task: **M0-1**.

## M0 — Foundation (G0)

- [ ] **M0-1** — Repo + lint + themes. Đầu ra: `README`, `docs/ADR`, Flutter chạy màn hình placeholder, theme fonts/colors, router, CI job `analyze/test`. PASS: clone mới chạy được, no warnings nghiêm trọng.
- [ ] **M0-2** — Design tokens + asset pipeline. Đầu ra: 5 giấy pastel, 2 loại ghim/băng dính, nền seamless tối ưu, shader/texture nhẹ, license log; fallback placeholder không tốn bộ nhớ. PASS: assets không méo ở các tỷ lệ màn hình, texture tái dùng chứ không upload PNG khổng lồ.
- [ ] **M0-3** — Contract shared models. Tạo freezed/json_serializable nếu thấy cần, hoặc dùng handwritten models tối giản; domain types cho `NoteTile`, `NoteDetail`, `WorldCell`, `WallRegion`, `PlacementResult`, `Conversation`, `Message`. PASS: unit tests serialize/deserialize và invalid models. Không bind trực tiếp row Supabase lên UI.

## M1 — Offline 2D Wall (G1)

- [ ] **M1-1** — Flame world & camera:** World, CameraComponent, pan 4 hướng, pinch anchored focal point, zoom clamp, bounds infinite virtual. PASS trên máy thật: pinch không nhảy, không kéo cả khi nhấn note.
- [ ] **M1-2** — Note component:** 50–100 note seeded deterministic, mỗi giấy 118×145 world units, lưới 180, style seeded, paper flutter lệch pha; animation off khi reduced motion. PASS: chibi nhẹ, mượt, không chồng tap target.
- [ ] **M1-3** — Tap to open:** world→screen rect, Flutter overlay chuyển giấy ra màn hình đọc, backdrop dim, close animation về note; không fetch network. PASS: open/close 30 lần, không leak overlay, back hoạt động.
- [ ] **M1-4** — TileManager & LOD:** chunks 8×8 cell, culling + LRU + mock 10k note, zoomed out clustering, no excessive components. PASS: profile 10 phút, không tăng RAM liên tục, frame time đo trong DevTools và ghi vào `PERF_REPORT.md`.
- [ ] **M1-5** — Placement POC:** ghost paper, snap cell, occupancy preview, confirm/cancel, collision local fake, deterministic transform. PASS: không thể đặt 2 giấy vào cùng ô trong local POC.

## M2 — Real shared wall + Supabase (G2)

- [ ] **M2-1** — Auth and Terms:** email OTP auth, custom SMTP cấu hình DEV/BETA, session, 18+ declaration, terms consent, onboarding, logout. PASS: user không chưa consent không được post.
- [ ] **M2-2** — Schema migration 001:** tables profiles, notes, daily_note_creations, wall_regions; status constraints, keys, indexes; RLS deny by default; protected read projection. PASS: `supabase db reset` clean, SQL tests complete.
- [ ] **M2-3** — Canonical coordinate functions:** floor division số âm; world-to-cell; tile indices; unique active occupancy; allocation suggestion. PASS: cùng tọa độ trên hai client, no overlap; collision server authoritative.
- [ ] **M2-4** — API `get_wall_tiles`, `get_note_detail`, `get_discovery_target`:** minimization DTO (no author_id/content in tiles), viewport limit, pagination. PASS: two devices see same layout, A cannot identify author via public API.
- [ ] **M2-5** — `place_note` transaction:** one-note/day VN regardless delete, idempotency, moderation status, unique cell occupancy, confirmation. PASS: concurrency tests two accounts simultaneous, 2 requests same client ID, quota deletion bypass fails.
- [ ] **M2-6** — Note composer & placement integration:** draft, keyboard, error states; local preview; success/review/error; note own jump. PASS: manual E2E with 2 devices, force-network-off recovery.
- [ ] **M2-7** — `edit_note`/`delete_note`/`update_note_chat`:** server rule 30m/no interaction, tombstone; tile invalidation. PASS: author only; delete removes from public wall.

## M3 — Encouragement/chat (G3)

- [ ] **M3-1** — Encouragement schema and endpoint:** templates, uniqueness, block checks, idempotency, notice to owner. PASS: owner cannot self-encourage, retry duplicates none, sender identity hidden.
- [ ] **M3-2** — Inbox:** summaries, unread local/store sync, no public sender identity, empty/error/offline states. PASS: encouragement visible after recipient reconnects.
- [ ] **M3-3** — Conversation schema + create:** one pair unique with canonical participant ordering, source note context, caller cannot select recipient ID, no notification until first message. PASS: same pair across 2 notes reused; irrelevant user access denied.
- [ ] **M3-4** — Transactional `send_message`:** count streak lock, membership/block/status, idempotency and rate limit. PASS: 3→block 4th→other side reply→reset; concurrent 4 sends still max 3.
- [ ] **M3-5** — Realtime & push-safe events:** private Broadcast subscribed only for involved parties, token refresh, reconnect fetch delta; wall tile invalidation. PASS: third account denied channel access, no body leaked in public payload.
- [ ] **M3-6** — Conversation UI:** simple bubble chat, character count, 3/3 lock status, sender labels, close/block/report action, keyboard/back/resume. PASS: correct remaining quota after app restart and from 2nd device.

## M4 — Safety/closed beta (G4)

- [ ] **M4-1** — Report/block:** report note/message/conversation/user, user block from note/conversation, two-direction enforcement; moderation reasons. PASS: victim can immediately stop new contact.
- [ ] **M4-2** — Moderation pipeline:** filter note/message, flagged/pending/hidden states, queue; no automatic publishing of risky content. PASS: flagged test fixtures held/handled predictably; manual actions audited.
- [ ] **M4-3** — Admin console:** minimal protected web page or internal tool (Next.js optional), role-based audit, report queue, hide/remove/suspend/resolve, contact/support. PASS: normal user cannot access admin pages/RPC.
- [ ] **M4-4** — Account deletion/data retention:** in-app request, revoke tokens, hide public content immediately, purge/anonymize subject to policy, export request handling if legally required. PASS: no public note after delete and no account access.
- [ ] **M4-5** — Observability + notification:** Crashlytics + FCM/APNs, key metrics, budget alerts, DB backup restore rehearsal; do not log contents. PASS: notifications neutral and disabled gracefully if permission denied.
- [ ] **M4-6** — QA/perf/accessibility:** 10k–100k seeded notes DB, simultaneous clients, p95 frame data, text scaling, TalkBack, offline/reconnect, race conditions, battery/reduced motion. PASS: known issues documented and release blockers fixed.
- [ ] **M4-7** — Legal/store readiness:** terms/privacy/support, Vietnam compliance review, age eligibility, store UGC moderation requirements, Apple anonymous chat review risk, release notes, data safety disclosures. PASS: owner signs off release checklist; legal blockers remain blockers.

## Gates / releases
- [ ] **G0** — Flutter foundation compiled/tested on available tools
- [ ] **G1** — Offline wall POC measured on Android
- [ ] **G2** — Two-device shared wall + RLS/concurrency proven
- [ ] **G3** — Encouragement + 3-message chat proven by backend tests
- [ ] **G4** — Report, block, moderation, delete, privacy, operations ready for closed beta
- [ ] **PRODUCTION** — owner approval, privacy/legal and store review, QA, backups

Current planned tasks: **28**.


---

# J — ENGINEERING RUNBOOK

SOURCE FILE: `docs/08_SETUP_AND_ENGINEERING_RUNBOOK.md`

# 08 — Local setup, CI and development runbook

**Codex must inspect actual SDK and OS capabilities before choosing commands.** Commands below are intent-level reference, not a claim that they ran on the user's computer.

## Prerequisites
- Git and private GitHub repository.
- Flutter stable SDK and Android SDK/emulator or real Android device, `flutter doctor -v` passes Android blockers.
- Dart comes with Flutter. For iOS build/testing, macOS + Xcode + Apple developer account are separate prerequisites.
- Supabase CLI + Docker or compatible runtime for local Supabase. If unavailable, keep mocked repos in M1 and record setup blocker for M2.
- A DEV Supabase project distinct from production. Never use production DB for generated seeds/stress tests.

## Bootstrap by Codex at M0-1
```bash
flutter doctor -v
flutter create --org app.tuongnho app
cd app
flutter pub add flame flutter_riverpod go_router supabase_flutter
flutter pub get
flutter analyze
flutter test
```
Codex should determine the current compatible versions, inspect API docs and commit lockfile. Don't install every Firebase/visual package at M0. If `flutter create` rejects a target directory or package name, adapt while preserving repo structure. Avoid mixing Android/iOS bundle identifiers accidentally.

## Supabase dev setup (from M2)
```bash
supabase init          # from repo root if no supabase/ config exists
supabase start         # Docker runtime needed
supabase db reset      # LOCAL ONLY; destructive to local db
supabase test db
```
**Never run `supabase db reset` on production**. All schema through checked-in migrations. Separate staging, beta and production keys; use a simple secret manager or CI secrets, not committed `.env`.

## App configuration
Use `--dart-define` / `--dart-define-from-file` in local development as supported by installed toolchain. A client SUPABASE URL + publishable key are not privileged server secrets, but still environment-specific. Do NOT put service-role keys, admin private keys, FCM server credentials or SMTP tokens in Dart/client. Server secrets stay in provider secret store and edge-function environment.

`.env.example` is documentation only; Codex can implement a `.env.dev.json.example` for Flutter define values during M2 and add real local files to `.gitignore`.

## Architecture / data flow
- Presentation (Flutter) → application/controller (Riverpod) → domain use case → repository interface → Supabase RPC/Edge client.
- Wall game (Flame) listens to only a light `WallTileRepository` and `WallViewModel` streams for visible region; content body isn't passed to world sprites.
- UI can use mock implementations in M1; replace with real Supabase repositories in M2 without changing game component business logic.
- Realtime is an invalidation/notification signal, not a source of truth. Refetch canonical authenticated server records after signal.
- Session expiry and reconnect require reauth/refetch; local drafts remain available until confirmed published.

## Error handling and offline
- All requests cancel/ignore stale responses on camera movement and lifecycle transitions.
- Network lost: wall can show cached tile metadata; user actions that require server (post, send, block, report) must show pending/error and never show false confirmation.
- Duplicate retry preserves `client_request_id`. Retry only for transient errors; don't hammer forbidden/rate-limit codes.
- New account/device logout must clear private in-memory state and private cache. No fake anonymous users in seeded production data.

## CI minimum after M0
- `dart format --output=none --set-exit-if-changed .` (run in app if paths apply)
- `flutter analyze`
- `flutter test`
- Validate migrations via Supabase local test job when available; run SQL/permission tests on DEV or CI postgres with proper `auth.uid()` context.
- Add secret scan and dependency audit where tooling permits. Build APK/test artifacts for PR checkpoints; do not auto publish.

## Progress tracking format
Each step updates `docs/PROGRESS.md` with date/time, task ID, summary, files, exact commands, PASS/FAIL/NOT RUN, device QA evidence and outstanding blockers. Do not modify design/business spec without ADR explaining reason and owner approval where needed.

## Test accounts
A (note owner), B (reader/chat sender), C (unauthorized unrelated actor), MOD (protected moderator role). Never include real personal phone numbers, private emails or login credentials in code, logs, documentation or screenshots. DEV seed uses generated test-only accounts and fictional note bodies labeled as fixtures.

## Escalation criteria
Stop only when external credentials, legal compliance decision, service charges, destructive production action, app store publish, or missing tooling truly blocks further independent development. Otherwise continue with next planned task. This is an implementation brief, not permission for hidden production actions.


---

# K — RELEASE & OPERATIONS

SOURCE FILE: `docs/09_RELEASE_OPERATIONS.md`

# TƯỜNG NHỎ — OPERATIONS, BUDGET & RELEASE CHECKLIST

**Source of truth product logic:** `00_MASTER_SPEC.md`. Số tiền là mức giá/ước tính tham khảo tại 2026-10-23 (USD; chưa thuế/phí vượt quota).

## 1. Ngân sách dự kiến

| Khoản | Dev/POC | Closed beta | Khi tăng trưởng |
|---|---:|---:|---|
| Flutter, Flame | $0 | $0 | $0 |
| Supabase | $0 Free | từ $25/tháng Pro khi cần | tính theo MAU, egress, DB, realtime, compute |
| Email SMTP | local Mailpit / plan test | ước $0–20/tháng | theo email gửi, reputation, domain |
| AI coding | tùy gói, ước $0–40/tháng | tương tự | theo token/plan |
| Domain | chưa bắt buộc | ước $10–20/năm | tương tự |
| Push FCM/APNs | không tính phí cơ bản cho FCM | chi phí vận hành theo dịch vụ phụ nếu có | theo mức sử dụng liên quan |
| Monitoring khác | thường Free tier | theo gói | theo usage |
| Kiểm duyệt, pháp lý, hỗ trợ | **chưa tính** | **bắt buộc dự trù riêng** | có thể lớn hơn hạ tầng |
| Apple Developer Program | — | $99/năm nếu phát hành iOS | duy trì hằng năm |
| Google Play Console | — | $25 một lần | kiểm tra chính sách phát hành |

**Planning range:** Dev $0–40/tháng nếu dùng tool free/AI thấp. Beta dùng dịch vụ trả phí cơ bản khoảng **$25–100/tháng** trước moderation/legal/test device costs. **Không coi đây là báo giá** hay dự toán đã đo tải.

Nguồn: https://supabase.com/pricing ; https://supabase.com/docs/guides/platform/billing-on-supabase ; https://developer.apple.com/programs/ ; https://support.google.com/googleplay/android-developer/answer/6112435 ; https://supabase.com/docs/guides/auth/auth-smtp

### 1.1 Capacity estimates, phải load-test thay vì đoán

- Một note plain text trung bình vài trăm byte đến vài KB chưa gồm row/index overhead; 100k/1M note phải đánh giá size thực tế PostgreSQL bằng sample production-like.
- Free Supabase giới hạn 500 MB DB; ở quy mô lớn, số note không phải chi phí duy nhất — messages/indexes/audit và Realtime có thể đáng kể.
- Pro bắt đầu từ $25 nhưng egress/compute/realtime tăng theo sử dụng; bật `spend cap`/usage alerts và audit phát sinh.
- Realtime không phát live từng note theo từng camera frame; chỉ event invalidate và private chat/inbox.

## 2. Environments

**local:** Supabase CLI, Mailpit, sample seed 1000/10000/100000 notes. **staging/beta:** project Supabase riêng, bộ test accounts, crash logs, email SMTP riêng. **production:** project riêng, migrations release reviewed, backup/restore plan, admin access hạn chế.

- Never copy production personal data to staging.
- Migrations append-only; rollback plan bằng migration thuận hoặc restore, không assume rollback tự động.
- Mobile app phải tương thích schema/API đang deploy; server không đổi breaking contract khi app cũ còn ngoài store.
- Backup do service cung cấp không thay thế kiểm thử restore. Document RTO/RPO phù hợp trước production.

## 3. Release checklist theo thứ tự

### Trước closed beta

- [ ] Auth OTP email verified, custom SMTP.
- [ ] Terms/Privacy/Community Guidelines và hỗ trợ liên hệ.
- [ ] Người dùng 18+ theo eligibility model và legal review về xác thực cần thiết.
- [ ] Report + Block hoạt động trên note và chat, có admin xử lý thực tế.
- [ ] Moderation active, người điều hành chịu trách nhiệm và xác định lịch xử lý.
- [ ] Kiểm thử leak dữ liệu/author ID, cố tình thử đọc tin nhắn người khác.
- [ ] Core transaction race tests run trong DB thật.
- [ ] Sẵn sàng tài liệu xử lý nội dung nhạy cảm và sự cố abuse.
- [ ] Theo dõi Supabase usage, logs tối giản, crash reporting.
- [ ] Seed notes bằng người thật đồng ý; không tạo fake encouragement để che vấn đề cold start.

### Trước production

- [ ] Vietnam legal applicability: Decree 147/2024, Law 91/2025, Decree 356/2025 và các văn bản/sửa đổi hiện hành được tư vấn.
- [ ] Apple App Review §1.2 risk reviewed vì có trò chuyện ẩn danh; logic/screenshot/listing nhấn mạnh nhật ký được kiểm duyệt và chat gắn với note, không chat ngẫu nhiên.
- [ ] Google Play UGC policy, Data Safety form, account deletion, test track requirements checked.
- [ ] Threat model, backup restoration drill, privacy audit, pentest/light security assessment tùy nguồn lực.
- [ ] P0/P1 bugs closed; benchmark trên mobile thật; README support/incident.
- [ ] App age rating, store screenshots, app review credentials/demo mode, privacy policy URL hoạt động.
- [ ] Phiên bản app, release notes và migration order được ghi lại.

## 4. Incident response tối thiểu

- **Security/privacy breach:** disable affected RPC/feature via server flag, preserve safe audit evidence, revoke tokens/keys as needed, đánh giá nghĩa vụ thông báo theo luật áp dụng.
- **Spam burst:** rate-limit author/post, hold pending review, tạm ngắt onboarding mới nếu cần, không tắt reporting.
- **Moderation overload:** giới hạn public posting, queue pre-review, rõ ràng status pending; không để nội dung đáng ngại tự được publish để chạy KPI.
- **DB/Realtime outage:** UI trạng thái offline, đọc cached tiles nếu an toàn, disable submit/retry with idempotency; avoid showing false success.
- **Mất chất lượng hiệu năng:** remote reduce animation feature flag, decrease fetched region size/LOD, rollback app version if feasible.

## 5. Final acceptance sign-off template

```markdown
Release candidate: vX.Y.Z / build ...
Date: ...
Spec version: 1.0.0
Android tested devices: ...
iOS tested devices (if relevant): ...
DB migrations: ...
Security/RLS tests: PASS/FAIL (logs link)
Concurrency tests: PASS/FAIL
End-to-end tests: PASS/FAIL
Accessibility/reduced motion: PASS/FAIL
Moderator readiness: PASS/FAIL
Legal/store gate: PASS/FAIL/BLOCKED
Known high-risk issues: ...
Rollback/runbook location: ...
Owner decision: APPROVE / REJECT
```

## 6. Source reference list

- Supabase billing: https://supabase.com/docs/guides/platform/billing-on-supabase
- Supabase auth SMTP: https://supabase.com/docs/guides/auth/auth-smtp
- Apple App Review: https://developer.apple.com/app-store/review/guidelines/
- Google Play UGC: https://support.google.com/googleplay/android-developer/answer/9876937
- Apple membership: https://developer.apple.com/programs/
- Google Play registration: https://support.google.com/googleplay/android-developer/answer/6112435
- Vietnamese legislation: https://vanban.chinhphu.vn/?classid=0&docid=211654&pageid=27160 ; https://vanban.chinhphu.vn/?classid=1&docid=214590&pageid=27160&typegroup= ; https://vanban.chinhphu.vn/?classid=1&docid=216387&orggroupid=2&pageid=27160


---

# L — DECISIONS

SOURCE FILE: `docs/07_DECISION_REGISTER.md`

# 07 — Frozen decisions vs beta assumptions

**Frozen (do NOT silently change):**
- Single global wall; fixed coordinates; discovery spawn changes only camera entry.
- Flutter mobile, Flame world, Supabase backend, PostgreSQL.
- Small paper unreadable until tapped, warm chibi/pastel editorial style, flutter with reduce-motion.
- Posting requires login and 18+ gate; public anonymous writer to community, private service ownership.
- Three social interactions only: journal note, private predefined encouragement, 1:1 chat.
- 3 consecutive unreplied messages PER user pair, enforced by DB transaction.
- Blocking, reports, content moderation, data deletion and admin safety needed pre-beta.
- No public profiles, follows, likes, public comments, photos/video, AI impersonation, random friend matching.

**Beta assumptions (tunable with metrics, require ADR if changed):**
| Setting | Initial value |
|---|---|
| Note max | 1000 grapheme clusters and 6KB UTF-8 |
| Message max | 500 grapheme clusters and 3KB UTF-8 |
| Daily posting | 1 per calendar day Asia/Ho_Chi_Minh, deletion does not reset |
| Note edit | <=30 minutes & before first interaction |
| Note expiration | none; appears weathered as ages; owner/admin can remove |
| Colors | 5 pastel variants |
| Paper dimensions | 118×145 world units |
| Cell spacing | 180 world units each axis |
| Tile size | 8×8 cells |
| Zoom clamp | 0.45–2.2 (device tuned) |
| Discovery weighting | 40% unencouraged; 35% recent; 25% random eligible regions |
| Encouragement | five predefined sentences, one per sender/note |
| Auth | Supabase email OTP; revisit applicable local identity law before public launch |
| Default moderation | filter and hold uncertain/unsafe note until reviewed |
| New chat | note's `allow_chat=true`; existing pair conversation persists when toggled off later |
| Age requirement | 18+ (declaration in MVP, not verified identity unless required) |

**Privacy caveat (must communicate):** Pair-level conversation reuse means a person who chats from several notes may infer those notes share a writer. Anonymous to community does not mean absolute unlinkability or cryptographic anonymity. This is a known trade-off; never promise otherwise.

**Open owner/legal gates:** Privacy/terms version, app store IDs, confirmed availability of human moderation, data storage/retention/cross-border policy, applicable local verification duties, age declaration sufficiency, messaging moderation flow, service region, support contact. See `docs/OPEN_QUESTIONS.md`.
