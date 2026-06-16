<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { models } from '$lib/stores';
	import {
		getAdminTokenfunUsageModels,
		getAdminTokenfunUsageSummary,
		getAdminTokenfunUsageUsers
	} from '$lib/apis/tokenfun-usage';
	import { getUserChatCounts } from '$lib/apis/analytics';
	import Spinner from '$lib/components/common/Spinner.svelte';
	import ChevronUp from '$lib/components/icons/ChevronUp.svelte';
	import ChevronDown from '$lib/components/icons/ChevronDown.svelte';
	import { WEBUI_API_BASE_URL } from '$lib/constants';
	import { decodeString, formatNumber } from '$lib/utils';

	const maxRangeDays = 31;
	const daySeconds = 86400;
	const toDateInput = (date: Date) => {
		const year = date.getFullYear();
		const month = `${date.getMonth() + 1}`.padStart(2, '0');
		const day = `${date.getDate()}`.padStart(2, '0');
		return `${year}-${month}-${day}`;
	};
	const today = toDateInput(new Date());
	const defaultStartDate = toDateInput(new Date(Date.now() - 6 * daySeconds * 1000));
	const startDateStorageKey = 'analyticsStartDateLocal';
	const endDateStorageKey = 'analyticsEndDateLocal';
	const analyticsCostVisibilityStorageKey = 'analyticsShowCosts';

	let startDate =
		typeof localStorage !== 'undefined'
			? (localStorage.getItem(startDateStorageKey) ?? defaultStartDate)
			: defaultStartDate;
	let endDate =
		typeof localStorage !== 'undefined'
			? (localStorage.getItem(endDateStorageKey) ?? today)
			: today;

	let summary = {
		request_count: 0,
		total_tokens: 0,
		prompt_tokens: 0,
		completion_tokens: 0,
		cost_usd: 0,
		cost_display: '$0.000000'
	};
	let modelStats: Array<any> = [];
	let userStats: Array<any> = [];
	let loading = true;
	let usersLoading = false;
	let csvLoading = '';
	let tokenfunError = '';
	let showAnalyticsCosts =
		typeof localStorage !== 'undefined'
			? localStorage.getItem(analyticsCostVisibilityStorageKey) === 'true'
			: false;

	let modelOrderBy = 'count';
	let modelDirection: 'asc' | 'desc' = 'desc';
	let userOrderBy: 'request_count' | 'total_tokens' = 'total_tokens';
	let userDirection: 'asc' | 'desc' = 'desc';
	let userPage = 1;
	let userTotal = 0;
	const userPageSize = 20;
	const exportModelPageSize = 100;
	const exportUserPageSize = 100;

	const parseDate = (value: string) => {
		const [year, month, day] = value.split('-').map((part) => Number(part));
		if (!year || !month || !day) {
			return null;
		}
		return new Date(year, month - 1, day);
	};

	const clampDateRange = () => {
		let start = parseDate(startDate) ?? new Date(Date.now() - 6 * daySeconds * 1000);
		let end = parseDate(endDate) ?? new Date();

		if (start > end) {
			start = new Date(end);
		}

		const maxStart = new Date(end.getTime() - (maxRangeDays - 1) * daySeconds * 1000);
		if (start < maxStart) {
			start = maxStart;
		}

		startDate = toDateInput(start);
		endDate = toDateInput(end);
	};

	const getDateRange = () => {
		clampDateRange();
		const start = parseDate(startDate);
		const end = parseDate(endDate);
		const startTimestamp = Math.floor((start ?? new Date()).getTime() / 1000);
		const endDateTime = end ?? new Date();
		endDateTime.setHours(23, 59, 59, 999);
		const endTimestamp = Math.floor(endDateTime.getTime() / 1000);
		return { start: startTimestamp, end: endTimestamp };
	};

	const formatCost = (item: any) =>
		item?.cost_display ?? `$${Number(item?.cost_usd ?? 0).toFixed(6)}`;

	const mergeUserStatsById = (items: Array<any>) => {
		const merged = new Map<string, any>();
		for (const item of items) {
			const userId = item.external_user_id || '';
			if (!userId) {
				continue;
			}

			const current = merged.get(userId);
			if (!current) {
				merged.set(userId, { ...item });
				continue;
			}

			const latest =
				Number(item.last_seen_at ?? 0) >= Number(current.last_seen_at ?? 0) ? item : current;
			const costUsd = Number(current.cost_usd ?? 0) + Number(item.cost_usd ?? 0);

			merged.set(userId, {
				...current,
				external_username: latest.external_username || current.external_username,
				external_user_email: latest.external_user_email || current.external_user_email,
				first_seen_at: Math.min(
					Number(current.first_seen_at ?? item.first_seen_at ?? 0),
					Number(item.first_seen_at ?? current.first_seen_at ?? 0)
				),
				last_seen_at: Math.max(
					Number(current.last_seen_at ?? item.last_seen_at ?? 0),
					Number(item.last_seen_at ?? current.last_seen_at ?? 0)
				),
				request_count: Number(current.request_count ?? 0) + Number(item.request_count ?? 0),
				prompt_tokens: Number(current.prompt_tokens ?? 0) + Number(item.prompt_tokens ?? 0),
				completion_tokens:
					Number(current.completion_tokens ?? 0) + Number(item.completion_tokens ?? 0),
				total_tokens: Number(current.total_tokens ?? 0) + Number(item.total_tokens ?? 0),
				quota: Number(current.quota ?? 0) + Number(item.quota ?? 0),
				cost_usd: costUsd,
				cost_display: `$${costUsd.toFixed(6)}`
			});
		}

		return [...merged.values()];
	};

	const mergeModelStatsByName = (items: Array<any>) => {
		const merged = new Map<string, any>();
		for (const item of items) {
			const modelName = item.model_name || '';
			if (!modelName) {
				continue;
			}

			const current = merged.get(modelName);
			if (!current) {
				merged.set(modelName, { ...item });
				continue;
			}

			const costUsd = Number(current.cost_usd ?? 0) + Number(item.cost_usd ?? 0);
			merged.set(modelName, {
				...current,
				request_count: Number(current.request_count ?? 0) + Number(item.request_count ?? 0),
				prompt_tokens: Number(current.prompt_tokens ?? 0) + Number(item.prompt_tokens ?? 0),
				completion_tokens:
					Number(current.completion_tokens ?? 0) + Number(item.completion_tokens ?? 0),
				total_tokens: Number(current.total_tokens ?? 0) + Number(item.total_tokens ?? 0),
				quota: Number(current.quota ?? 0) + Number(item.quota ?? 0),
				cost_usd: costUsd,
				cost_display: `$${costUsd.toFixed(6)}`
			});
		}

		return [...merged.values()];
	};

	const loadCostVisibility = () => {
		showAnalyticsCosts =
			typeof localStorage !== 'undefined'
				? localStorage.getItem(analyticsCostVisibilityStorageKey) === 'true'
				: false;
	};

	const compareNumber = (a: number, b: number, direction: 'asc' | 'desc') =>
		direction === 'asc' ? a - b : b - a;

	const csvValue = (value: any) => {
		const text = value === undefined || value === null ? '' : `${value}`;
		return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
	};

	const buildCsv = (rows: any[][]) =>
		`\ufeff${rows.map((row) => row.map(csvValue).join(',')).join('\n')}`;

	const downloadCsvFile = (filename: string, rows: any[][]) => {
		const csv = buildCsv(rows);
		const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
		const url = URL.createObjectURL(blob);
		const link = document.createElement('a');
		link.href = url;
		link.download = filename;
		document.body.appendChild(link);
		link.click();
		link.remove();
		URL.revokeObjectURL(url);
	};

	const buildModelCsvRows = (items: Array<any>) => {
		const rows: any[][] = [['名称', 'API请求', 'Tokens', '输入', '输出']];
		if (showAnalyticsCosts) {
			rows[0].push('费用');
		}

		for (const model of items) {
			const row = [
				model.name || model.model_name,
				model.request_count,
				model.total_tokens,
				model.prompt_tokens ?? '',
				model.completion_tokens ?? ''
			];
			if (showAnalyticsCosts) {
				row.push(formatCost(model));
			}
			rows.push(row);
		}
		return rows;
	};

	const buildUserCsvRows = (items: Array<any>) => {
		const rows: any[][] = [['名称', '邮箱', '用户ID', 'API请求', '对话', 'Tokens', '输入', '输出']];
		if (showAnalyticsCosts) {
			rows[0].push('费用');
		}

		for (const item of items) {
			const row = [
				item._display_username || item._display_user_email || item.external_user_id,
				item._display_user_email || '',
				item.external_user_id,
				item.request_count,
				item.chat_count,
				item.total_tokens,
				item.prompt_tokens ?? '',
				item.completion_tokens ?? ''
			];
			if (showAnalyticsCosts) {
				row.push(formatCost(item));
			}
			rows.push(row);
		}
		return rows;
	};

	const sortModelStats = (items: Array<any>) =>
		[...items].sort((a, b) => {
			if (modelOrderBy === 'name') {
				const nameA = a.name || a.model_name;
				const nameB = b.name || b.model_name;
				return modelDirection === 'asc' ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
			}
			if (modelOrderBy === 'tokens') {
				return compareNumber(
					Number(a.total_tokens ?? 0),
					Number(b.total_tokens ?? 0),
					modelDirection
				);
			}
			if (modelOrderBy === 'cost') {
				return compareNumber(Number(a.cost_usd ?? 0), Number(b.cost_usd ?? 0), modelDirection);
			}
			return compareNumber(
				Number(a.request_count ?? 0),
				Number(b.request_count ?? 0),
				modelDirection
			);
		});

	const loadAllModelStatsForExport = async (start: number, end: number) => {
		const modelsMap = new Map($models.map((m) => [m.id, m.name || m.id]));
		const allItems = [];
		let page = 1;

		while (true) {
			const res = await getAdminTokenfunUsageModels(
				localStorage.token,
				start,
				end,
				page,
				exportModelPageSize
			);
			const currentItems = res?.data?.items ?? [];
			allItems.push(...currentItems);
			if (currentItems.length < exportModelPageSize) {
				break;
			}
			page += 1;
		}

		return sortModelStats(
			mergeModelStatsByName(allItems).map((entry: any) => ({
				...entry,
				name: modelsMap.get(entry.model_name) || entry.model_name
			}))
		);
	};

	const loadAllUserStatsForExport = async (start: number, end: number) => {
		const allItems = [];
		let page = 1;

		while (true) {
			const res = await getAdminTokenfunUsageUsers(
				localStorage.token,
				start,
				end,
				page,
				exportUserPageSize,
				'',
				'',
				userOrderBy,
				userDirection
			);
			const currentItems = res?.data?.items ?? [];
			allItems.push(...currentItems);
			if (currentItems.length < exportUserPageSize) {
				break;
			}
			page += 1;
		}

		const allUsers = mergeUserStatsById(allItems).map((entry: any) => ({
			...entry,
			_display_username: entry.external_username ? decodeString(entry.external_username) : '',
			_display_user_email: entry.external_user_email ? decodeString(entry.external_user_email) : ''
		}));
		if (allUsers.length > 0) {
			try {
				const countsRes = await getUserChatCounts(localStorage.token, start, end);
				const counts = new Map(
					(countsRes?.users ?? []).map((entry: any) => [
						entry.user_id,
						Number(entry.chat_count ?? 0)
					])
				);
				return allUsers.map((entry) => ({
					...entry,
					chat_count: counts.get(entry.external_user_id) ?? 0
				}));
			} catch (err) {
				console.error('Failed to load local chat counts for export:', err);
			}
		}

		return allUsers.map((entry) => ({
			...entry,
			chat_count: 0
		}));
	};

	const downloadModelCsv = async () => {
		const { start, end } = getDateRange();
		csvLoading = 'models';
		try {
			const allModels = await loadAllModelStatsForExport(start, end);
			downloadCsvFile(
				`analytics-model-usage-${startDate}-${endDate}.csv`,
				buildModelCsvRows(allModels)
			);
		} catch (err) {
			console.error('Failed to download model usage csv:', err);
		} finally {
			csvLoading = '';
		}
	};

	const downloadUserCsv = async () => {
		const { start, end } = getDateRange();
		csvLoading = 'users';
		try {
			const allUsers = await loadAllUserStatsForExport(start, end);
			downloadCsvFile(
				`analytics-user-activity-${startDate}-${endDate}.csv`,
				buildUserCsvRows(allUsers)
			);
		} catch (err) {
			console.error('Failed to download user activity csv:', err);
		} finally {
			csvLoading = '';
		}
	};

	const toggleModelSort = (key: string) => {
		if (modelOrderBy === key) {
			modelDirection = modelDirection === 'asc' ? 'desc' : 'asc';
		} else {
			modelOrderBy = key;
			modelDirection = key === 'name' ? 'asc' : 'desc';
		}
	};

	const toggleUserSort = (key: 'request_count' | 'total_tokens') => {
		if (userOrderBy === key) {
			userDirection = userDirection === 'asc' ? 'desc' : 'asc';
		} else {
			userOrderBy = key;
			userDirection = 'desc';
		}
		loadUserPage(1);
	};

	const updateUserStats = (usersRes: any) => {
		userTotal = Number(usersRes?.data?.total ?? 0);
		userStats = mergeUserStatsById(usersRes?.data?.items ?? []).map((entry: any) => ({
			...entry,
			chat_count: 0,
			_display_username: entry.external_username ? decodeString(entry.external_username) : '',
			_display_user_email: entry.external_user_email ? decodeString(entry.external_user_email) : ''
		}));
	};

	const applyUserChatCounts = async (items: Array<any>, start: number, end: number) => {
		const userIds = items.map((entry) => entry.external_user_id).filter(Boolean);
		if (userIds.length === 0) {
			return items;
		}

		try {
			const res = await getUserChatCounts(localStorage.token, start, end, userIds);
			const counts = new Map(
				(res?.users ?? []).map((entry: any) => [entry.user_id, Number(entry.chat_count ?? 0)])
			);
			return items.map((entry) => ({
				...entry,
				chat_count: counts.get(entry.external_user_id) ?? 0
			}));
		} catch (err) {
			console.error('Failed to load local chat counts:', err);
		}
		return items;
	};

	const loadUserPage = async (page = userPage) => {
		usersLoading = true;
		tokenfunError = '';
		try {
			const { start, end } = getDateRange();
			userPage = Math.max(1, page);
			const usersRes = await getAdminTokenfunUsageUsers(
				localStorage.token,
				start,
				end,
				userPage,
				userPageSize,
				'',
				'',
				userOrderBy,
				userDirection
			);
			updateUserStats(usersRes);
			userStats = await applyUserChatCounts(userStats, start, end);
		} catch (err) {
			tokenfunError = typeof err === 'string' ? err : JSON.stringify(err);
			userStats = [];
			userTotal = 0;
		} finally {
			usersLoading = false;
		}
	};

	const loadDashboard = async () => {
		loading = true;
		tokenfunError = '';
		try {
			const { start, end } = getDateRange();
			if (typeof localStorage !== 'undefined') {
				localStorage.setItem(startDateStorageKey, startDate);
				localStorage.setItem(endDateStorageKey, endDate);
			}

			userPage = 1;
			const modelsMap = new Map($models.map((m) => [m.id, m.name || m.id]));
			const [summaryRes, modelsRes, usersRes] = await Promise.all([
				getAdminTokenfunUsageSummary(localStorage.token, start, end),
				getAdminTokenfunUsageModels(localStorage.token, start, end, 1, 50),
				getAdminTokenfunUsageUsers(
					localStorage.token,
					start,
					end,
					userPage,
					userPageSize,
					'',
					'',
					userOrderBy,
					userDirection
				)
			]);
			summary = summaryRes?.data ?? summary;
			modelStats = (modelsRes?.data?.items ?? []).map((entry: any) => ({
				...entry,
				name: modelsMap.get(entry.model_name) || entry.model_name
			}));
			updateUserStats(usersRes);
			userStats = await applyUserChatCounts(userStats, start, end);
		} catch (err) {
			tokenfunError = typeof err === 'string' ? err : JSON.stringify(err);
			summary = {
				request_count: 0,
				total_tokens: 0,
				prompt_tokens: 0,
				completion_tokens: 0,
				cost_usd: 0,
				cost_display: '$0.000000'
			};
			modelStats = [];
			userStats = [];
		} finally {
			loading = false;
		}
	};

	$: sortedModels = sortModelStats(modelStats);

	$: sortedUsers = userStats;

	$: userPageCount = Math.max(1, Math.ceil(userTotal / userPageSize));
	$: userStartIndex = userTotal === 0 ? 0 : (userPage - 1) * userPageSize + 1;
	$: userEndIndex = Math.min(userPage * userPageSize, userTotal);

	onMount(() => {
		loadCostVisibility();
		window.addEventListener('analytics-cost-visibility-change', loadCostVisibility);
		loadDashboard();
	});

	onDestroy(() => {
		window.removeEventListener('analytics-cost-visibility-change', loadCostVisibility);
	});
</script>

<div
	class="pt-0.5 pb-2 gap-2 flex flex-col md:flex-row md:justify-between md:items-center sticky top-0 z-10 bg-white dark:bg-gray-900"
>
	<div>
		<div class="text-lg font-medium px-0.5 shrink-0">分析</div>
	</div>
	<div class="flex items-center gap-2 flex-wrap justify-end min-w-0">
		<input
			type="date"
			bind:value={startDate}
			max={endDate}
			class="rounded-sm border border-gray-200 bg-transparent px-2 py-1 text-xs outline-none dark:border-gray-800"
			aria-label="开始日期"
			on:change={loadDashboard}
		/>
		<span class="text-xs text-gray-400">至</span>
		<input
			type="date"
			bind:value={endDate}
			min={startDate}
			class="rounded-sm border border-gray-200 bg-transparent px-2 py-1 text-xs outline-none dark:border-gray-800"
			aria-label="结束日期"
			on:change={loadDashboard}
		/>
		<button
			class="rounded-sm border border-gray-200 px-2 py-1 text-xs hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-850"
			on:click={downloadModelCsv}
			disabled={loading || csvLoading !== ''}
		>
			{csvLoading === 'models' ? '导出中...' : '下载模型 CSV'}
		</button>
		<button
			class="rounded-sm border border-gray-200 px-2 py-1 text-xs hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-800 dark:hover:bg-gray-850"
			on:click={downloadUserCsv}
			disabled={loading || csvLoading !== ''}
		>
			{csvLoading === 'users' ? '导出中...' : '下载用户 CSV'}
		</button>
		<button
			class="rounded-sm border border-gray-200 px-2 py-1 text-xs hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-850"
			on:click={loadDashboard}
		>
			刷新
		</button>
	</div>
</div>

{#if tokenfunError}
	<div
		class="mb-3 rounded-md border border-yellow-200 bg-yellow-50 px-3 py-2 text-xs text-yellow-800 dark:border-yellow-900 dark:bg-yellow-950 dark:text-yellow-100"
	>
		tokenfun 用量暂不可用：{tokenfunError}
	</div>
{/if}

{#if loading}
	<div class="my-10 flex justify-center">
		<Spinner className="size-5" />
	</div>
{:else}
	<div class="flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400 px-0.5 pb-3">
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.request_count)}</span
			>
			API请求
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.total_tokens)}</span
			>
			tokens
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.prompt_tokens)}</span
			>
			输入
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.completion_tokens)}</span
			>
			输出
		</span>
		{#if showAnalyticsCosts}
			<span>
				<span class="font-medium text-gray-900 dark:text-gray-300">{formatCost(summary)}</span>
				费用
			</span>
		{/if}
	</div>

	<div class="grid md:grid-cols-2 gap-4">
		<div>
			<div class="text-xs font-medium text-gray-700 dark:text-gray-300 mb-1 px-0.5">模型用量</div>
			<div class="scrollbar-hidden relative whitespace-nowrap overflow-x-auto max-w-full">
				<table class="w-full text-sm text-left text-gray-500 dark:text-gray-400 table-auto">
					<thead class="text-xs text-gray-800 uppercase bg-transparent dark:text-gray-200">
						<tr class="border-b-[1.5px] border-gray-50 dark:border-gray-850/30">
							<th scope="col" class="px-2.5 py-2 w-8">#</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none"
								on:click={() => toggleModelSort('name')}
							>
								<div class="flex gap-1.5 items-center">
									模型
									{#if modelOrderBy === 'name'}
										{#if modelDirection === 'asc'}<ChevronUp
												className="size-2"
											/>{:else}<ChevronDown className="size-2" />{/if}
									{:else}
										<span class="invisible"><ChevronUp className="size-2" /></span>
									{/if}
								</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleModelSort('count')}
							>
								<div class="flex gap-1.5 items-center justify-end">API请求</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleModelSort('tokens')}
							>
								<div class="flex gap-1.5 items-center justify-end">Tokens</div>
							</th>
							{#if showAnalyticsCosts}
								<th
									scope="col"
									class="px-2.5 py-2 cursor-pointer select-none text-right"
									on:click={() => toggleModelSort('cost')}
								>
									<div class="flex gap-1.5 items-center justify-end">
										费用
										{#if modelOrderBy === 'cost'}
											{#if modelDirection === 'asc'}<ChevronUp
													className="size-2"
												/>{:else}<ChevronDown className="size-2" />{/if}
										{:else}
											<span class="invisible"><ChevronUp className="size-2" /></span>
										{/if}
									</div>
								</th>
							{/if}
						</tr>
					</thead>
					<tbody>
						{#each sortedModels as model, idx (model.model_name)}
							<tr class="bg-white dark:bg-gray-900 dark:border-gray-850 text-xs">
								<td class="px-3 py-1 text-gray-400">{idx + 1}</td>
								<td class="px-3 py-1 font-medium text-gray-900 dark:text-white">
									<div class="flex items-center gap-2">
										<img
											src="{WEBUI_API_BASE_URL}/models/model/profile/image?id={model.model_name}"
											alt={model.name}
											class="size-5 rounded-full object-cover shrink-0"
											on:error={(e) => {
												(e.currentTarget as HTMLImageElement).src = '/favicon.png';
											}}
										/>
										<span class="truncate max-w-[180px]">{model.name}</span>
									</div>
								</td>
								<td class="px-3 py-1 text-right">{formatNumber(model.request_count)}</td>
								<td class="px-3 py-1 text-right">{formatNumber(model.total_tokens)}</td>
								{#if showAnalyticsCosts}
									<td class="px-3 py-1 text-right">{formatCost(model)}</td>
								{/if}
							</tr>
						{/each}
						{#if sortedModels.length === 0}
							<tr
								><td
									colspan={showAnalyticsCosts ? 5 : 4}
									class="px-3 py-2 text-center text-gray-400">暂无数据</td
								></tr
							>
						{/if}
					</tbody>
				</table>
			</div>
		</div>

		<div>
			<div class="mb-1 flex items-center justify-between gap-2 px-0.5">
				<div class="text-xs font-medium text-gray-700 dark:text-gray-300">用户动态</div>
				<div class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
					<span>{userStartIndex}-{userEndIndex} / {formatNumber(userTotal)}</span>
					<button
						type="button"
						class="rounded-sm border border-gray-200 px-2 py-0.5 disabled:cursor-not-allowed disabled:opacity-40 dark:border-gray-800"
						disabled={usersLoading || userPage <= 1}
						on:click={() => loadUserPage(userPage - 1)}
					>
						上一页
					</button>
					<button
						type="button"
						class="rounded-sm border border-gray-200 px-2 py-0.5 disabled:cursor-not-allowed disabled:opacity-40 dark:border-gray-800"
						disabled={usersLoading || userPage >= userPageCount}
						on:click={() => loadUserPage(userPage + 1)}
					>
						下一页
					</button>
				</div>
			</div>
			<div class="scrollbar-hidden relative whitespace-nowrap overflow-x-auto max-w-full">
				<table class="w-full text-sm text-left text-gray-500 dark:text-gray-400 table-auto">
					<thead class="text-xs text-gray-800 uppercase bg-transparent dark:text-gray-200">
						<tr class="border-b-[1.5px] border-gray-50 dark:border-gray-850/30">
							<th scope="col" class="px-2.5 py-2 w-8">#</th>
							<th scope="col" class="px-2.5 py-2">
								<div class="flex gap-1.5 items-center">用户</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleUserSort('request_count')}
							>
								<div class="flex gap-1.5 items-center justify-end">
									API请求
									{#if userOrderBy === 'request_count'}
										{#if userDirection === 'asc'}<ChevronUp className="size-2" />{:else}<ChevronDown
												className="size-2"
											/>{/if}
									{:else}
										<span class="invisible"><ChevronUp className="size-2" /></span>
									{/if}
								</div>
							</th>
							<th scope="col" class="px-2.5 py-2 text-right">
								<div class="flex gap-1.5 items-center justify-end">对话</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleUserSort('total_tokens')}
							>
								<div class="flex gap-1.5 items-center justify-end">
									Tokens
									{#if userOrderBy === 'total_tokens'}
										{#if userDirection === 'asc'}<ChevronUp className="size-2" />{:else}<ChevronDown
												className="size-2"
											/>{/if}
									{:else}
										<span class="invisible"><ChevronUp className="size-2" /></span>
									{/if}
								</div>
							</th>
							{#if showAnalyticsCosts}
								<th scope="col" class="px-2.5 py-2 text-right">
									<div class="flex gap-1.5 items-center justify-end">费用</div>
								</th>
							{/if}
						</tr>
					</thead>
					<tbody>
						{#each sortedUsers as item, idx (item.external_user_id)}
							<tr class="bg-white dark:bg-gray-900 dark:border-gray-850 text-xs">
								<td class="px-3 py-1 text-gray-400">{(userPage - 1) * userPageSize + idx + 1}</td>
								<td class="px-3 py-1 font-medium text-gray-900 dark:text-white">
									<div class="flex items-center gap-2">
										<img
											src="{WEBUI_API_BASE_URL}/users/{item.external_user_id}/profile/image"
											alt={item._display_username || 'User'}
											class="size-5 rounded-full object-cover shrink-0"
											on:error={(e) => {
												(e.currentTarget as HTMLImageElement).src = '/user.png';
											}}
										/>
										<span class="min-w-0">
											<span class="block truncate max-w-[160px]"
												>{item._display_username ||
													item._display_user_email ||
													item.external_user_id}</span
											>
											{#if item._display_user_email}
												<span class="block truncate max-w-[160px] text-[11px] text-gray-400"
													>{item._display_user_email}</span
												>
											{/if}
										</span>
									</div>
								</td>
								<td class="px-3 py-1 text-right">{formatNumber(item.request_count)}</td>
								<td class="px-3 py-1 text-right">{formatNumber(item.chat_count)}</td>
								<td class="px-3 py-1 text-right">{formatNumber(item.total_tokens)}</td>
								{#if showAnalyticsCosts}
									<td class="px-3 py-1 text-right">{formatCost(item)}</td>
								{/if}
							</tr>
						{/each}
						{#if sortedUsers.length === 0}
							<tr
								><td
									colspan={showAnalyticsCosts ? 6 : 5}
									class="px-3 py-2 text-center text-gray-400">暂无数据</td
								></tr
							>
						{/if}
					</tbody>
				</table>
			</div>
		</div>
	</div>
{/if}
