// PAI-CC 管理后台 JavaScript

// 配置
const API_BASE = 'http://100.64.0.13:8090/api/v1';

// 状态
let currentPage = 'dashboard';
let currentStudent = 'default';
let sessionTrendChart = null;
let mistakeDistributionChart = null;
let learningTrendChart = null;

// 工具函数
async function api(method, path, data = null) {
    const options = {
        method,
        headers: { 'Content-Type': 'application/json' }
    };
    if (data) options.body = JSON.stringify(data);

    try {
        const res = await fetch(API_BASE + path, options);
        if (!res.ok) {
            const error = await res.json().catch(() => ({ detail: '请求失败' }));
            throw new Error(error.detail || `HTTP ${res.status}`);
        }
        return await res.json();
    } catch (e) {
        console.error('API Error:', e);
        return { error: e.message };
    }
}

function formatDate(dateStr) {
    if (!dateStr) return '-';
    const d = new Date(dateStr);
    return d.toLocaleString('zh-CN');
}

function formatDateShort(dateStr) {
    if (!dateStr) return '-';
    const d = new Date(dateStr);
    return `${d.getMonth() + 1}/${d.getDate()}`;
}

function formatDuration(seconds) {
    if (!seconds) return '0分钟';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) {
        return m > 0 ? `${h}小时${m}分钟` : `${h}小时`;
    }
    return `${m}分钟`;
}

function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
}

function showModal(title, content, footer = '') {
    document.getElementById('modalTitle').textContent = title;
    document.getElementById('modalBody').innerHTML = content;
    document.getElementById('modalFooter').innerHTML = footer;
    document.getElementById('modal').classList.add('show');
}

function closeModal() {
    document.getElementById('modal').classList.remove('show');
}

// 页面切换
function switchPage(page) {
    currentPage = page;
    document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
    document.getElementById(`page-${page}`).classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.querySelector(`[data-page="${page}"]`).classList.add('active');

    document.getElementById('pageTitle').textContent = {
        dashboard: 'Dashboard',
        sessions: '会话管理',
        mistakes: '错题管理',
        review: '复习队列',
        profile: '学生画像',
        prompts: '提示词配置'
    }[page];

    loadPageData(page);
}

async function loadPageData(page) {
    switch(page) {
        case 'dashboard': loadDashboard(); break;
        case 'sessions': loadSessions(); break;
        case 'mistakes': loadMistakes(); break;
        case 'review': loadReview(); break;
        case 'profile': loadProfile(); break;
        case 'prompts': loadPrompts(); break;
    }
}

// Dashboard 数据加载
async function loadDashboard() {
    try {
        // 概览统计
        const overview = await api('GET', '/dashboard/overview');
        document.getElementById('statStudents').textContent = overview.total_students || 0;
        document.getElementById('statActiveToday').textContent = overview.active_students_today || 0;
        document.getElementById('statSessionsToday').textContent = overview.total_sessions_today || 0;
        document.getElementById('statCapturesToday').textContent = overview.total_captures_today || 0;

        // 会话趋势图
        const trends = await api('GET', '/dashboard/trends/sessions?days=7');
        if (trends.trends && trends.trends.length > 0) {
            drawSessionTrendChart(trends.trends);
        }

        // 错题分布
        const mistakeDist = await api('GET', '/dashboard/trends/mistakes');
        if (mistakeDist.distribution && mistakeDist.distribution.length > 0) {
            drawMistakeDistributionChart(mistakeDist.distribution);
        }

        // 薄弱知识点
        const weakTopics = await api('GET', '/dashboard/topics/weak');
        const weakList = document.getElementById('weakTopicsList');
        if (weakTopics.topics && weakTopics.topics.length > 0) {
            weakList.innerHTML = weakTopics.topics.slice(0, 5).map(t => `
                <div class="weak-topic-item">
                    <span>${t.topic}</span>
                    <span class="badge">${t.total_errors}次</span>
                </div>
            `).join('');
        } else {
            weakList.innerHTML = '<div class="empty">暂无数据</div>';
        }

        // 活跃学生
        const topStudents = await api('GET', '/dashboard/students/top');
        const studentsList = document.getElementById('topStudentsList');
        if (topStudents.students && topStudents.students.length > 0) {
            studentsList.innerHTML = topStudents.students.slice(0, 5).map((s, i) => `
                <div class="student-item">
                    <span class="rank">${i + 1}</span>
                    <span>${s.student_id}</span>
                    <span class="badge">${s.sessions_count}次</span>
                </div>
            `).join('');
        } else {
            studentsList.innerHTML = '<div class="empty">暂无数据</div>';
        }

        // 热力图
        const heatmap = await api('GET', '/dashboard/heatmap');
        drawHeatmap(heatmap);
    } catch (e) {
        console.error('Dashboard load error:', e);
    }
}

function drawSessionTrendChart(data) {
    const canvas = document.getElementById('sessionTrendChart');
    if (!canvas) return;

    if (sessionTrendChart) {
        sessionTrendChart.destroy();
    }

    const ctx = canvas.getContext('2d');
    const width = canvas.parentElement.clientWidth;
    const height = 250;
    canvas.width = width;
    canvas.height = height;

    sessionTrendChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: data.map(d => formatDateShort(d.date)),
            datasets: [{
                label: '会话数',
                data: data.map(d => d.sessions_count),
                backgroundColor: 'rgba(102, 126, 234, 0.8)',
                borderColor: 'rgba(102, 126, 234, 1)',
                borderWidth: 1,
                borderRadius: 6
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            const d = data[context.dataIndex];
                            return [
                                `会话: ${d.sessions_count}`,
                                `平均时长: ${d.avg_duration_minutes.toFixed(1)}分钟`,
                                `平均错题: ${d.avg_mistakes_per_session.toFixed(1)}`
                            ];
                        }
                    }
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: {
                        color: 'rgba(0, 0, 0, 0.05)'
                    }
                },
                x: {
                    grid: {
                        display: false
                    }
                }
            }
        }
    });
}

function drawMistakeDistributionChart(data) {
    const canvas = document.getElementById('mistakeDistributionChart');
    if (!canvas) return;

    if (mistakeDistributionChart) {
        mistakeDistributionChart.destroy();
    }

    const ctx = canvas.getContext('2d');

    mistakeDistributionChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: data.map(d => d.subject),
            datasets: [{
                data: data.map(d => d.count),
                backgroundColor: [
                    'rgba(102, 126, 234, 0.8)',
                    'rgba(118, 75, 162, 0.8)',
                    'rgba(72, 187, 120, 0.8)',
                    'rgba(237, 137, 54, 0.8)',
                    'rgba(245, 101, 101, 0.8)'
                ],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'right'
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            const d = data[context.dataIndex];
                            return `${d.subject}: ${d.count}题 (${d.percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

function drawHeatmap(data) {
    const container = document.getElementById('heatmapContainer');
    if (!data || !data.heatmap || !data.heatmap.length) {
        container.innerHTML = '<div class="empty">暂无数据</div>';
        return;
    }

    const dayNames = ['一', '二', '三', '四', '五', '六', '日'];
    const maxCount = Math.max(...data.heatmap.map(d => d.activity_count), 1);

    // 创建按天分组的热力图
    const byDay = {};
    data.heatmap.forEach(h => {
        if (!byDay[h.day_of_week]) byDay[h.day_of_week] = [];
        byDay[h.day_of_week].push(h);
    });

    let html = '<div class="heatmap-grid">';
    for (let day = 0; day < 7; day++) {
        html += `<div class="heatmap-row">`;
        html += `<div class="heatmap-day-label">周${dayNames[day]}</div>`;
        html += `<div class="heatmap-cells">`;
        if (byDay[day]) {
            byDay[day].forEach(h => {
                const intensity = h.activity_count / maxCount;
                html += `<div class="heatmap-cell" style="background: rgba(102, 126, 234, ${0.2 + intensity * 0.8})" title="${h.hour}:00 - ${h.activity_count}次活动"></div>`;
            });
        }
        html += `</div></div>`;
    }
    html += '</div>';

    container.innerHTML = html;
}

// 会话管理
async function loadSessions() {
    const status = document.getElementById('sessionStatusFilter').value;
    let url = '/sessions/';
    if (status) url += `?status=${status}`;

    const data = await api('GET', url);
    const tbody = document.querySelector('#sessionsTable tbody');

    if (data.sessions && data.sessions.length > 0) {
        tbody.innerHTML = data.sessions.map(s => `
            <tr>
                <td><span class="text-mono">${s.session_id.substring(0, 16)}...</span></td>
                <td><span class="badge badge-${s.status}">${getStatusText(s.status)}</span></td>
                <td>${s.student_goal || '-'}</td>
                <td>${s.capture_count || 0}</td>
                <td>${s.mistake_count || 0}</td>
                <td>${formatDate(s.created_at)}</td>
                <td>
                    <button class="btn btn-sm" onclick="viewSession('${s.session_id}')">查看</button>
                    ${s.status !== 'completed' ? `<button class="btn btn-sm btn-primary" onclick="endSession('${s.session_id}')">结束</button>` : ''}
                </td>
            </tr>
        `).join('');
    } else {
        tbody.innerHTML = '<tr><td colspan="7" class="empty">暂无会话记录</td></tr>';
    }
}

function getStatusText(status) {
    const map = {
        created: '创建中',
        active: '进行中',
        completed: '已完成',
        processing: '处理中'
    };
    return map[status] || status;
}

// 新建会话
async function createNewSession() {
    const studentGoal = prompt('请输入学习目标（可选）:', '');
    if (studentGoal === null) return;

    const result = await api('POST', '/sessions/', {
        student_id: currentStudent,
        student_goal: studentGoal || null,
        report_style: 'normal'
    });

    if (result.session_id) {
        showToast('会话创建成功', 'success');
        loadSessions();
    } else {
        showToast('创建失败: ' + (result.detail || '未知错误'), 'error');
    }
}

// 添加错题
async function addMistake() {
    showModal('添加错题', `
        <form id="addMistakeForm" class="mistake-form">
            <div class="form-group">
                <label>科目</label>
                <select id="newMistakeSubject" required>
                    <option value="">请选择科目</option>
                    <option value="数学">数学</option>
                    <option value="物理">物理</option>
                    <option value="化学">化学</option>
                    <option value="英语">英语</option>
                    <option value="其他">其他</option>
                </select>
            </div>
            <div class="form-group">
                <label>知识点</label>
                <input type="text" id="newMistakeTopic" placeholder="如：一元二次方程" required>
            </div>
            <div class="form-group">
                <label>题目内容</label>
                <textarea id="newMistakeQuestion" rows="3" placeholder="输入题目内容" required></textarea>
            </div>
            <div class="form-group">
                <label>正确答案</label>
                <input type="text" id="newMistakeAnswer" placeholder="正确答案">
            </div>
            <div class="form-group">
                <label>学生答案</label>
                <input type="text" id="newMistakeStudentAnswer" placeholder="学生的错误答案">
            </div>
            <div class="form-group">
                <label>错误类型</label>
                <select id="newMistakeErrorType">
                    <option value="">请选择</option>
                    <option value="计算错误">计算错误</option>
                    <option value="概念混淆">概念混淆</option>
                    <option value="审题不清">审题不清</option>
                    <option value="知识点遗忘">知识点遗忘</option>
                    <option value="其他">其他</option>
                </select>
            </div>
            <div class="form-group">
                <label>难度 (0-1)</label>
                <input type="range" id="newMistakeDifficulty" min="0" max="1" step="0.1" value="0.5">
                <span id="difficultyDisplay">0.5</span>
            </div>
        </form>
    `, `
        <button class="btn" onclick="closeModal()">取消</button>
        <button class="btn btn-primary" onclick="submitNewMistake()">添加</button>
    `);

    // 难度滑块事件
    document.getElementById('newMistakeDifficulty').addEventListener('input', (e) => {
        document.getElementById('difficultyDisplay').textContent = e.target.value;
    });
}

async function submitNewMistake() {
    const data = {
        student_id: currentStudent,
        subject: document.getElementById('newMistakeSubject').value,
        topic: document.getElementById('newMistakeTopic').value,
        question_text: document.getElementById('newMistakeQuestion').value,
        correct_answer: document.getElementById('newMistakeAnswer').value || null,
        student_answer: document.getElementById('newMistakeStudentAnswer').value || null,
        error_type: document.getElementById('newMistakeErrorType').value || null,
        difficulty: parseFloat(document.getElementById('newMistakeDifficulty').value)
    };

    if (!data.subject || !data.topic || !data.question_text) {
        showToast('请填写必填项', 'warning');
        return;
    }

    const result = await api('POST', '/mistakes', data);
    if (result.mistake_id) {
        showToast('错题添加成功', 'success');
        closeModal();
        loadMistakes();
    } else {
        showToast('添加失败', 'error');
    }
}

// 同步复习队列
async function syncReviewQueue() {
    const result = await api('POST', `/review-queue/sync?student_id=${currentStudent}`);
    if (result.status === 'synced') {
        showToast(`已同步 ${result.added} 个错题到复习队列`, 'success');
        loadReview();
    } else {
        showToast('同步失败', 'error');
    }
}

async function viewSession(sessionId) {
    const session = await api('GET', `/sessions/${sessionId}`);
    const stats = await api('GET', `/sessions/${sessionId}/stats`);

    showModal('会话详情', `
        <div class="detail-grid">
            <div><label>会话ID</label><span class="text-mono">${session.session_id}</span></div>
            <div><label>状态</label><span class="badge badge-${session.status}">${getStatusText(session.status)}</span></div>
            <div><label>学生ID</label><span>${session.student_id || '-'}</span></div>
            <div><label>学习目标</label><span>${session.student_goal || '-'}</span></div>
            <div><label>会话时长</label><span>${formatDuration(stats.duration_seconds)}</span></div>
            <div><label>截图数</label><span>${session.capture_count || 0}</span></div>
            <div><label>错题数</label><span>${session.mistake_count || 0}</span></div>
            <div><label>学习项数</label><span>${session.learning_item_count || 0}</span></div>
            <div><label>相机活跃占比</label><span>${stats.camera_active_ratio}%</span></div>
            <div><label>专注度评分</label><span>${stats.student_attention_score}</span></div>
            <div><label>完成率</label><span>${stats.completion_rate}%</span></div>
            <div><label>创建时间</label><span>${formatDate(session.created_at)}</span></div>
            ${session.started_at ? `<div><label>开始时间</label><span>${formatDate(session.started_at)}</span></div>` : ''}
            ${session.ended_at ? `<div><label>结束时间</label><span>${formatDate(session.ended_at)}</span></div>` : ''}
        </div>
        ${session.report ? `
        <div class="session-report">
            <h4>学习报告</h4>
            <div class="report-content">${JSON.stringify(session.report, null, 2)}</div>
        </div>
        ` : ''}
    `);
}

async function endSession(sessionId) {
    if (!confirm('确定要结束这个会话吗？')) return;
    const result = await api('POST', `/sessions/${sessionId}/end`);
    if (result.session_id) {
        showToast('会话已结束', 'success');
        loadSessions();
    } else {
        showToast('结束失败', 'error');
    }
}

// 错题管理
async function loadMistakes() {
    const subject = document.getElementById('mistakeSubjectFilter').value;
    const status = document.getElementById('mistakeStatusFilter').value;
    let url = '/mistakes';
    const params = [];
    if (subject) params.push(`subject=${subject}`);
    if (status) params.push(`status=${status}`);
    if (params.length) url += '?' + params.join('&');

    const data = await api('GET', url);
    const tbody = document.querySelector('#mistakesTable tbody');

    // 更新统计
    const stats = await api('GET', '/mistakes/stats/summary');
    document.getElementById('mistakesTotal').textContent = stats.total || 0;
    document.getElementById('mistakesNew').textContent = stats.by_status?.new || 0;
    document.getElementById('mistakesReviewing').textContent = stats.by_status?.reviewing || 0;
    document.getElementById('mistakesMastered').textContent = stats.by_status?.mastered || 0;

    if (data.length > 0) {
        tbody.innerHTML = data.map(m => `
            <tr>
                <td>${m.subject || '-'}</td>
                <td>${m.topic || '-'}</td>
                <td><span class="text-ellipsis" title="${m.question_text}">${(m.question_text || '').substring(0, 30)}...</span></td>
                <td>${m.error_type || '-'}</td>
                <td>${getDifficultyText(m.difficulty)}</td>
                <td><span class="badge badge-${m.status}">${getMistakeStatusText(m.status)}</span></td>
                <td>${m.review_count || 0}</td>
                <td>
                    <button class="btn btn-sm" onclick="viewMistake('${m.mistake_id}')">详情</button>
                    ${m.status !== 'mastered' ? `<button class="btn btn-sm btn-success" onclick="markMastered('${m.mistake_id}')">掌握</button>` : ''}
                </td>
            </tr>
        `).join('');
    } else {
        tbody.innerHTML = '<tr><td colspan="8" class="empty">暂无错题记录</td></tr>';
    }
}

function getDifficultyText(difficulty) {
    if (difficulty === undefined || difficulty === null) return '-';
    if (difficulty < 0.3) return '简单';
    if (difficulty < 0.7) return '中等';
    return '困难';
}

function getMistakeStatusText(status) {
    const map = {
        new: '新建',
        reviewing: '复习中',
        mastered: '已掌握'
    };
    return map[status] || status;
}

async function viewMistake(mistakeId) {
    const mistake = await api('GET', `/mistakes/${mistakeId}`);
    const reviewEvents = await api('GET', `/mistakes/${mistakeId}/review-events`);

    showModal('错题详情', `
        <div class="detail-grid">
            <div><label>科目</label><span>${mistake.subject || '-'}</span></div>
            <div><label>知识点</label><span>${mistake.topic || '-'}</span></div>
            <div><label>错误类型</label><span>${mistake.error_type || '-'}</span></div>
            <div><label>难度</label><span>${getDifficultyText(mistake.difficulty)}</span></div>
            <div><label>状态</label><span class="badge badge-${mistake.status}">${getMistakeStatusText(mistake.status)}</span></div>
            <div><label>复习次数</label><span>${mistake.review_count || 0}</span></div>
            <div><label>创建时间</label><span>${formatDate(mistake.created_at)}</span></div>
            <div><label>最近复习</label><span>${formatDate(mistake.last_reviewed_at)}</span></div>
        </div>
        <div class="mistake-content-section">
            <h4>题目</h4>
            <div class="mistake-content">${mistake.question_text || '-'}</div>
        </div>
        <div class="mistake-content-section">
            <h4>正确答案</h4>
            <div class="mistake-content">${mistake.correct_answer || '-'}</div>
        </div>
        <div class="mistake-content-section">
            <h4>学生答案</h4>
            <div class="mistake-content">${mistake.student_answer || '-'}</div>
        </div>
        ${reviewEvents.events && reviewEvents.events.length > 0 ? `
        <div class="review-events-section">
            <h4>复习历史</h4>
            <div class="review-events-list">
                ${reviewEvents.events.map(e => `
                    <div class="review-event-item">
                        <span class="event-result badge badge-${e.result}">${e.result}</span>
                        <span class="event-time">${formatDate(e.created_at)}</span>
                        ${e.notes ? `<span class="event-notes">${e.notes}</span>` : ''}
                    </div>
                `).join('')}
            </div>
        </div>
        ` : ''}
    `);
}

async function markMastered(mistakeId) {
    const result = await api('PUT', `/mistakes/${mistakeId}/master`);
    if (result.mistake_id) {
        showToast('已标记为掌握', 'success');
        loadMistakes();
    } else {
        showToast('操作失败', 'error');
    }
}

// 复习队列
async function loadReview() {
    const status = document.getElementById('reviewStatusFilter').value;
    let url = `/review-queue?student_id=${currentStudent}`;
    if (status) url += `&status=${status}`;

    const data = await api('GET', url);

    // 统计数据
    const stats = await api('GET', `/review-queue/stats/${currentStudent}`);
    document.getElementById('reviewTotal').textContent = stats.total_items || 0;
    document.getElementById('reviewDueToday').textContent = stats.due_today || 0;
    document.getElementById('reviewDueWeek').textContent = stats.due_this_week || 0;
    document.getElementById('reviewOverdue').textContent = stats.overdue || 0;

    // 复习列表
    const list = document.getElementById('reviewList');
    if (data.items && data.items.length > 0) {
        list.innerHTML = data.items.map(q => {
            const isOverdue = new Date(q.due_date) < new Date();
            const statusClass = q.interval >= 30 ? 'mastered' : (isOverdue ? 'overdue' : 'due');
            return `
            <div class="review-item ${statusClass}">
                <div class="review-info">
                    <span class="review-question">${(q.question_text || '').substring(0, 80)}...</span>
                    <div class="review-meta">
                        <span>下次复习: ${formatDate(q.due_date)}</span>
                        <span>间隔: ${q.interval}天</span>
                        <span>复习: ${q.repetitions}次</span>
                        <span>难度: ${getDifficultyText(q.difficulty)}</span>
                    </div>
                </div>
                <div class="review-actions">
                    <button class="btn btn-success btn-sm" onclick="submitReview('${q.queue_id}', 5)">完全掌握</button>
                    <button class="btn btn-primary btn-sm" onclick="submitReview('${q.queue_id}', 4)">记住</button>
                    <button class="btn btn-warning btn-sm" onclick="submitReview('${q.queue_id}', 2)">困难</button>
                    <button class="btn btn-danger btn-sm" onclick="submitReview('${q.queue_id}', 0)">遗忘</button>
                </div>
            </div>
        `}).join('');
    } else {
        list.innerHTML = '<div class="empty">暂无待复习项</div>';
    }
}

async function submitReview(queueId, quality) {
    const res = await api('POST', `/review-queue/${queueId}/review`, { quality });
    if (res.queue_id) {
        const message = res.is_mastered ? '已掌握！' : `下次复习: ${formatDate(res.next_review_date)}`;
        showToast(message, 'success');
        loadReview();
    }
}

// 学生画像
async function loadProfile() {
    const studentId = currentStudent;

    try {
        // 获取学生画像
        const profile = await api('GET', `/student-profile/${studentId}`);
        const stats = await api('GET', `/student-profile/${studentId}/stats`);
        const subjects = await api('GET', `/student-profile/${studentId}/subjects`);
        const weaknesses = await api('GET', `/student-profile/${studentId}/weaknesses`);
        const habits = await api('GET', `/student-profile/${studentId}/habits`);

        // 学习概况
        const summary = document.getElementById('profileSummary');
        summary.innerHTML = `
            <div class="profile-stat">
                <span class="value">${stats.total_sessions || 0}</span>
                <span class="label">学习会话</span>
            </div>
            <div class="profile-stat">
                <span class="value">${stats.total_mistakes || 0}</span>
                <span class="label">错题数</span>
            </div>
            <div class="profile-stat">
                <span class="value">${stats.mastered_count || 0}</span>
                <span class="label">已掌握</span>
            </div>
            <div class="profile-stat">
                <span class="value">${stats.accuracy_rate || 0}%</span>
                <span class="label">正确率</span>
            </div>
            <div class="profile-stat">
                <span class="value">${stats.streak_days || 0}</span>
                <span class="label">连续天数</span>
            </div>
            <div class="profile-stat">
                <span class="value">${getStudyTimeText(habits)}</span>
                <span class="label">学习时段</span>
            </div>
        `;

        // 科目分析图表
        if (subjects.length > 0) {
            drawSubjectAnalysisChart(subjects);
            const subjectAnalysis = document.getElementById('subjectAnalysis');
            subjectAnalysis.innerHTML = subjects.map(s => `
                <div class="subject-item">
                    <span class="subject-name">${s.subject}</span>
                    <div class="subject-bar">
                        <div class="subject-bar-track">
                            <div class="subject-bar-fill" style="width: ${s.accuracy_rate}%; background: ${getAccuracyColor(s.accuracy_rate)};"></div>
                        </div>
                        <span class="subject-bar-value">${s.accuracy_rate}%</span>
                    </div>
                </div>
            `).join('');
        } else {
            document.getElementById('subjectAnalysis').innerHTML = '<div class="empty">暂无科目数据</div>';
        }

        // 薄弱点分析
        const weaknessAnalysis = document.getElementById('weaknessAnalysis');
        if (weaknesses.length > 0) {
            weaknessAnalysis.innerHTML = weaknesses.map(w => `
                <div class="weakness-item">
                    <div class="weakness-info">
                        <span class="weakness-topic">${w.topic}</span>
                        <span class="weakness-errors">${w.error_count}次错误</span>
                    </div>
                    <div class="weakness-meta">
                        <span>建议练习: ${w.suggested_practice_count}次</span>
                    </div>
                </div>
            `).join('');
        } else {
            weaknessAnalysis.innerHTML = '<div class="empty">暂无薄弱点</div>';
        }

        // 学习趋势图
        loadLearningTrend('week');
    } catch (e) {
        console.error('Profile load error:', e);
    }
}

function getStudyTimeText(habits) {
    const map = {
        morning: '上午',
        afternoon: '下午',
        evening: '晚上',
        night: '深夜',
        unknown: '未知'
    };
    return map[habits?.preferred_study_time] || '未知';
}

function getAccuracyColor(rate) {
    if (rate >= 80) return 'var(--success)';
    if (rate >= 60) return 'var(--warning)';
    return 'var(--danger)';
}

function drawSubjectAnalysisChart(data) {
    const canvas = document.getElementById('subjectAnalysisChart');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');

    if (window.subjectChart) {
        window.subjectChart.destroy();
    }

    window.subjectChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: data.map(d => d.subject),
            datasets: [{
                label: '正确率',
                data: data.map(d => d.accuracy_rate),
                backgroundColor: data.map(d => getAccuracyColor(d.accuracy_rate)),
                borderRadius: 6
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100,
                    grid: { color: 'rgba(0,0,0,0.05)' }
                },
                x: { grid: { display: false } }
            }
        }
    });
}

async function loadLearningTrend(period) {
    const canvas = document.getElementById('learningTrendChart');
    if (!canvas) return;

    const trend = await api('GET', `/student-profile/${currentStudent}/trend?period=${period}`);
    const ctx = canvas.getContext('2d');

    if (learningTrendChart) {
        learningTrendChart.destroy();
    }

    const labels = trend.accuracy_trend?.map((_, i) => `Day ${i + 1}`) || [];

    learningTrendChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [
                {
                    label: '正确率',
                    data: trend.accuracy_trend || [],
                    borderColor: 'rgba(102, 126, 234, 1)',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    fill: true,
                    tension: 0.4
                },
                {
                    label: '学习时长',
                    data: trend.effort_trend?.map(t => t / 60) || [],
                    borderColor: 'rgba(72, 187, 120, 1)',
                    backgroundColor: 'rgba(72, 187, 120, 0.1)',
                    fill: false,
                    tension: 0.4
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { position: 'top' }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: { color: 'rgba(0,0,0,0.05)' }
                },
                x: { grid: { display: false } }
            }
        }
    });

    // 更新按钮状态
    document.querySelectorAll('.trend-controls .btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.period === period);
    });
}

// 提示词配置
let promptTemplates = [
    { id: '1', name: '详细解答', content: '请详细解答这道题目，包括解题步骤、知识点讲解和易错点提示。' },
    { id: '2', name: '举一反三', content: '请根据这道题目的知识点，出一道类似的练习题。' },
    { id: '3', name: '概念讲解', content: '请讲解这个概念的本质含义，并举例说明。' }
];

async function loadPrompts() {
    // 加载提示词模板
    const templatesList = document.getElementById('templatesList');
    templatesList.innerHTML = promptTemplates.map(t => `
        <div class="template-item">
            <div class="template-header">
                <span class="template-name">${t.name}</span>
                <div class="template-actions">
                    <button class="btn btn-xs" onclick="editTemplate('${t.id}')">编辑</button>
                    <button class="btn btn-xs btn-danger" onclick="deleteTemplate('${t.id}')">删除</button>
                </div>
            </div>
            <div class="template-content">${t.content}</div>
        </div>
    `).join('');

    // 加载温度滑块值
    document.getElementById('temperature').addEventListener('input', (e) => {
        document.getElementById('temperatureValue').textContent = e.target.value;
    });
}

function editTemplate(id) {
    const template = promptTemplates.find(t => t.id === id);
    if (!template) return;

    const newContent = prompt('编辑模板内容:', template.content);
    if (newContent && newContent !== template.content) {
        template.content = newContent;
        showToast('模板已更新', 'success');
        loadPrompts();
    }
}

function deleteTemplate(id) {
    if (!confirm('确定要删除这个模板吗？')) return;
    promptTemplates = promptTemplates.filter(t => t.id !== id);
    showToast('模板已删除', 'success');
    loadPrompts();
}

async function saveSystemPrompt() {
    const prompt = document.getElementById('systemPrompt').value;
    // 本地存储
    localStorage.setItem('pai_cc_system_prompt', prompt);
    showToast('系统提示词已保存', 'success');
}

function resetSystemPrompt() {
    const defaultPrompt = `你是一位专业、耐心、富有同理心的AI学习陪伴助手。你的目标是帮助学生理解和掌握知识，培养良好的学习习惯，发现并补足知识薄弱点。在回答问题时，要循序渐进、深入浅出，同时注意引导学生主动思考，培养独立解决问题的能力。`;
    document.getElementById('systemPrompt').value = defaultPrompt;
}

async function saveAIConfig() {
    const config = {
        temperature: parseFloat(document.getElementById('temperature').value),
        max_tokens: parseInt(document.getElementById('maxTokens').value),
        history_length: parseInt(document.getElementById('historyLength').value)
    };
    localStorage.setItem('pai_cc_ai_config', JSON.stringify(config));
    showToast('AI配置已保存', 'success');
}

// 初始化
document.addEventListener('DOMContentLoaded', () => {
    // 导航点击
    document.querySelectorAll('.nav-item').forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            switchPage(item.dataset.page);
        });
    });

    // 模态框关闭
    document.getElementById('modalClose').addEventListener('click', closeModal);
    document.getElementById('modal').addEventListener('click', (e) => {
        if (e.target.id === 'modal') closeModal();
    });

    // 刷新按钮
    document.getElementById('refreshBtn').addEventListener('click', () => loadPageData(currentPage));

    // 学生选择
    document.getElementById('studentSelect').addEventListener('change', (e) => {
        currentStudent = e.target.value;
        loadPageData(currentPage);
    });

    // 保存提示词
    document.getElementById('savePromptBtn').addEventListener('click', saveSystemPrompt);
    document.getElementById('resetPromptBtn').addEventListener('click', resetSystemPrompt);
    document.getElementById('saveConfigBtn').addEventListener('click', saveAIConfig);

    // 添加模板按钮
    document.getElementById('addTemplateBtn').addEventListener('click', () => {
        const name = prompt('输入模板名称:');
        if (name) {
            const content = prompt('输入模板内容:');
            if (content) {
                promptTemplates.push({
                    id: Date.now().toString(),
                    name: name,
                    content: content
                });
                showToast('模板已添加', 'success');
                loadPrompts();
            }
        }
    });

    // 趋势控制按钮
    document.querySelectorAll('.trend-controls .btn').forEach(btn => {
        btn.addEventListener('click', () => {
            loadLearningTrend(btn.dataset.period);
        });
    });

    // 移动端菜单
    document.getElementById('menuToggle').addEventListener('click', () => {
        document.getElementById('sidebar').classList.toggle('open');
        document.getElementById('overlay').classList.toggle('show');
    });

    document.getElementById('overlay').addEventListener('click', () => {
        document.getElementById('sidebar').classList.remove('open');
        document.getElementById('overlay').classList.remove('show');
    });

    // 加载初始数据
    loadDashboard();
    checkApiStatus();
});

// API 状态检查
async function checkApiStatus() {
    const statusEl = document.getElementById('apiStatus');
    try {
        const res = await fetch('http://100.64.0.13:8090/health');
        const data = await res.json();
        if (data.status === 'healthy') {
            statusEl.innerHTML = `
                <span class="status-dot status-online"></span>
                <span class="status-text">已连接</span>
            `;
        } else {
            statusEl.innerHTML = `
                <span class="status-dot status-error"></span>
                <span class="status-text">异常</span>
            `;
        }
    } catch (e) {
        statusEl.innerHTML = `
            <span class="status-dot status-error"></span>
            <span class="status-text">未连接</span>
        `;
    }
}

// 辅助样式
const style = document.createElement('style');
style.textContent = `
    .text-mono { font-family: monospace; font-size: 12px; }
    .text-ellipsis { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: inline-block; }
    .mistake-content-section { margin-top: 20px; }
    .mistake-content-section h4 { font-size: 14px; color: var(--gray-600); margin-bottom: 8px; }
    .mistake-content { padding: 12px; background: var(--gray-50); border-radius: 8px; line-height: 1.6; }
    .review-events-section { margin-top: 20px; }
    .review-events-section h4 { font-size: 14px; color: var(--gray-600); margin-bottom: 12px; }
    .review-event-item { display: flex; align-items: center; gap: 12px; padding: 8px 0; border-bottom: 1px solid var(--gray-100); }
    .review-event-item:last-child { border-bottom: none; }
    .event-time { color: var(--gray-500); font-size: 13px; }
    .event-notes { color: var(--gray-600); font-size: 13px; }
    .heatmap-grid { display: flex; flex-direction: column; gap: 4px; }
    .heatmap-row { display: flex; align-items: center; gap: 8px; }
    .heatmap-day-label { width: 50px; font-size: 12px; color: var(--gray-500); text-align: right; }
    .heatmap-cells { display: flex; gap: 3px; flex: 1; }
    .heatmap-cell { width: 16px; height: 16px; border-radius: 3px; cursor: pointer; transition: transform 0.2s; }
    .heatmap-cell:hover { transform: scale(1.2); }
    .weakness-info { display: flex; flex-direction: column; gap: 4px; }
    .weakness-topic { font-weight: 600; color: var(--gray-800); }
    .weakness-errors { font-size: 13px; color: var(--danger); }
    .weakness-meta { font-size: 13px; color: var(--gray-500); }
    .session-report { margin-top: 20px; }
    .session-report h4 { font-size: 14px; color: var(--gray-600); margin-bottom: 12px; }
    .report-content { padding: 12px; background: var(--gray-50); border-radius: 8px; font-family: monospace; font-size: 12px; white-space: pre-wrap; }
`;
document.head.appendChild(style);