<script lang="ts">
	import { getContext, onDestroy, onMount } from 'svelte';
	import type { Writable } from 'svelte/store';
	import type { i18n as i18nType } from 'i18next';

	const i18n = getContext<Writable<i18nType>>('i18n');

	export let size = 'md';
	export let status: any = null;

	const phrases = [
		'Thinking through your request...',
		'Working on a response...',
		'Putting the response together...',
		'Preparing the answer...',
		'Organizing the response...',
		'Shaping the answer...',
		'Still working on it...',
		'Giving this a little more thought...'
	];

	let phraseIndex = Math.floor(Math.random() * phrases.length);
	let rotationTimer: ReturnType<typeof setTimeout> | null = null;

	const readNumber = (value: any) => {
		const number = Number(value);
		return Number.isFinite(number) && number > 0 ? number : null;
	};

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

	$: retryCount = readNumber(
		findValue(status, ['retry_count', 'retryCount', 'retry_attempt', 'retryAttempt', 'attempt'])
	);
	$: retryLimit =
		readNumber(findValue(status, ['max_retries', 'maxRetries', 'retry_limit', 'retryLimit'])) ?? 3;
	$: statusDescription =
		typeof status?.description === 'string'
			? status.description
			: typeof status?.content === 'string'
				? status.content
				: '';
	$: displayText = retryCount
		? $i18n.t('Retrying response ({{current}}/{{total}})', {
				current: Math.min(retryCount, retryLimit),
				total: retryLimit
			})
		: statusDescription || $i18n.t(phrases[phraseIndex]);

	const scheduleRotation = () => {
		rotationTimer = setTimeout(
			() => {
				phraseIndex = (phraseIndex + 1) % phrases.length;
				scheduleRotation();
			},
			3000 + Math.floor(Math.random() * 2001)
		);
	};

	onMount(scheduleRotation);
	onDestroy(() => {
		if (rotationTimer) clearTimeout(rotationTimer);
	});
</script>

<div class="flex items-center gap-2 my-2 text-sm text-gray-500 dark:text-gray-400" role="status">
	<span
		class="relative flex {size === 'md'
			? 'size-3'
			: size === 'xs'
				? 'size-1.5'
				: 'size-2'} shrink-0 mx-1"
	>
		<span
			class="absolute inline-flex h-full w-full animate-pulse rounded-full bg-gray-700 dark:bg-gray-200 opacity-75"
		></span>
		<span
			class="relative inline-flex h-full w-full rounded-full bg-black dark:bg-white animate-size"
		></span>
	</span>
	<span aria-live="polite">{displayText}</span>
</div>

<style>
	@keyframes size {
		0%,
		100% {
			transform: scale(1);
		}
		50% {
			transform: scale(1.25);
		}
	}

	.animate-size {
		animation: size 1.5s ease-in-out infinite;
	}
</style>
