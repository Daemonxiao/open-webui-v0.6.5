<script lang="ts">
	import { getContext } from 'svelte';
	import type { Writable } from 'svelte/store';
	import type { i18n as i18nType } from 'i18next';
	import Info from '$lib/components/icons/Info.svelte';

	const i18n = getContext<Writable<i18nType>>('i18n');

	export let content: any = '';
	export let requestId: string | null = null;
	export let retryCount: number | null = null;
	export let onRegenerate: (() => void) | null = null;

	const findValue = (value: any, keys: string[], depth = 0): any => {
		if (!value || typeof value !== 'object' || depth > 3) return null;

		for (const key of keys) {
			if (value[key] !== undefined && value[key] !== null) return value[key];
		}

		for (const nested of Object.values(value)) {
			const result = findValue(nested, keys, depth + 1);
			if (result !== null) return result;
		}

		return null;
	};

	$: resolvedRequestId =
		requestId ??
		findValue(content, ['request_id', 'requestId', 'x_request_id', 'xRequestId', 'trace_id']);
	$: resolvedRetryCount =
		retryCount ??
		findValue(content, ['retry_count', 'retryCount', 'retry_attempt', 'retryAttempt', 'attempt']);
	$: rawError =
		typeof content === 'string'
			? content
			: content === true
				? ''
				: JSON.stringify(content, null, 2);
</script>

<div class="my-2 border px-4 py-3 border-red-600/10 bg-red-600/10 rounded-lg">
	<div class="flex gap-2.5">
		<Info className="size-5 text-red-700 dark:text-red-400" />

		<div class="min-w-0 flex-1">
			<div class="text-sm text-gray-900 dark:text-gray-100">
				<div class="font-medium">{$i18n.t('Response generation failed')}</div>
				<div class="mt-0.5">
					{$i18n.t('The model service is temporarily unavailable. Please regenerate.')}
				</div>
			</div>

			{#if onRegenerate}
				<button
					type="button"
					class="mt-2 rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-gray-700 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-200"
					on:click={onRegenerate}
				>
					{$i18n.t('Regenerate')}
				</button>
			{/if}

			{#if rawError || resolvedRequestId || resolvedRetryCount}
				<details class="mt-2 text-xs text-gray-600 dark:text-gray-400">
					<summary class="cursor-pointer select-none">{$i18n.t('Technical details')}</summary>
					<div class="mt-2 space-y-1">
						{#if resolvedRequestId}
							<div>
								<span class="font-medium">{$i18n.t('Request ID')}:</span>
								<code class="break-all">{resolvedRequestId}</code>
							</div>
						{/if}
						{#if resolvedRetryCount}
							<div>
								<span class="font-medium">{$i18n.t('Retry count')}:</span>
								{resolvedRetryCount}
							</div>
						{/if}
						{#if rawError}
							<pre class="whitespace-pre-wrap break-words font-mono">{rawError}</pre>
						{/if}
					</div>
				</details>
			{/if}
		</div>
	</div>
</div>
