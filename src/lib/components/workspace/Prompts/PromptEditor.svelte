<script lang="ts">
	import { onMount, tick, getContext } from 'svelte';

	import Textarea from '$lib/components/common/Textarea.svelte';
	import { toast } from 'svelte-sonner';
	import { slugify } from '$lib/utils';
	import Spinner from '$lib/components/common/Spinner.svelte';

	export let onSubmit: Function;
	export let edit = false;
	export let prompt: any = null;
	export let clone = false;
	export let disabled = false;

	const i18n = getContext('i18n');

	let loading = false;

	let name = '';
	let command = '';
	let description = '';
	let content = '';
	let tags = [];

	$: if (!edit) {
		command = name !== '' ? slugify(name) : '';
	}

	const submitHandler = async () => {
		if (disabled) {
			toast.error($i18n.t('You do not have permission to edit this prompt.'));
			return;
		}
		loading = true;

		const submitCommand = edit ? command : command || name || `prompt-app-${Date.now()}`;

		if (!edit || validateCommandString(submitCommand)) {
			try {
				await onSubmit({
					id: prompt?.id,
					name,
					command: submitCommand,
					description,
					content,
					tags: tags.map((tag) => tag.name),
					is_production: true
				});
			} catch (error) {
				toast.error(`${error}`);
			}
		} else {
			toast.error(
				$i18n.t('Only alphanumeric characters and hyphens are allowed in the command string.')
			);
		}

		loading = false;
	};

	const validateCommandString = (inputString) => {
		const regex = /^[a-zA-Z0-9-_]+$/;
		return regex.test(inputString);
	};

	onMount(async () => {
		if (prompt) {
			name = prompt.name || '';
			description = prompt.description || '';
			await tick();
			command = prompt.command.at(0) === '/' ? prompt.command.slice(1) : prompt.command;
			content = prompt.content;
			tags = (prompt.tags || []).map((tag) => ({ name: tag }));
		}
	});
</script>

<form
	class="mx-auto flex h-full max-h-[100dvh] w-full max-w-4xl flex-col gap-6 overflow-y-auto px-1 py-6 md:px-2"
	on:submit|preventDefault={submitHandler}
>
	<div class="flex items-start justify-between gap-4">
		<div class="min-w-0 flex-1">
			<div class="text-2xl font-semibold text-gray-900 dark:text-gray-100">
				{$i18n.t(edit ? 'Edit Prompt App' : 'Create Prompt App')}
			</div>
			<div class="mt-1 text-sm text-gray-500 dark:text-gray-400">
				{#if edit}
					{$i18n.t('Saved changes are used as the current version.')}
				{:else}
					{$i18n.t('Create a reusable prompt app for the chat input menu.')}
				{/if}
			</div>
		</div>

		{#if disabled}
			<span class="text-xs text-gray-500 bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded-full">
				{$i18n.t('Read Only')}
			</span>
		{:else}
			<button
				class="flex shrink-0 justify-center rounded-full bg-black px-5 py-2 text-sm font-medium text-white transition hover:bg-gray-900 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-white dark:text-black dark:hover:bg-gray-100"
				type="submit"
				disabled={loading}
			>
				<div>{$i18n.t(edit ? 'Save' : 'Save & Create')}</div>
				{#if loading}
					<div class="ml-1.5">
						<Spinner />
					</div>
				{/if}
			</button>
		{/if}
	</div>

	<div class="flex flex-col gap-5">
		<div>
			<div class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-200">
				{$i18n.t('Name')}
			</div>
			<input
				class="w-full rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm outline-hidden transition placeholder:text-gray-400 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-500 focus:border-gray-400 dark:border-gray-800 dark:bg-gray-900 dark:disabled:bg-gray-850 dark:disabled:text-gray-500 dark:focus:border-gray-600"
				placeholder={$i18n.t('Name')}
				bind:value={name}
				required
				disabled={disabled || edit}
			/>
			{#if edit}
				<div class="mt-1 text-xs text-gray-400 dark:text-gray-600">
					{$i18n.t('Prompt App name cannot be changed after creation.')}
				</div>
			{/if}
		</div>

		<div>
			<div class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-200">
				{$i18n.t('Description')}
			</div>
			<textarea
				class="w-full resize-none rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm outline-hidden transition placeholder:text-gray-400 disabled:cursor-not-allowed disabled:bg-gray-100 disabled:text-gray-500 focus:border-gray-400 dark:border-gray-800 dark:bg-gray-900 dark:disabled:bg-gray-850 dark:disabled:text-gray-500 dark:focus:border-gray-600"
				placeholder={$i18n.t('Describe when to use this prompt app.')}
				bind:value={description}
				rows="4"
				required
				{disabled}
			></textarea>
		</div>

		<div class="min-h-0 flex-1">
			<div class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-200">
				{$i18n.t('Prompt Content')}
			</div>
			<Textarea
				className="w-full rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm leading-7 outline-hidden overflow-y-hidden resize-none transition placeholder:text-gray-400 focus:border-gray-400 dark:border-gray-800 dark:bg-gray-900 dark:focus:border-gray-600"
				placeholder={$i18n.t('Write a summary in 50 words that summarizes {{topic}}.')}
				bind:value={content}
				rows={edit ? 18 : 16}
				minSize={edit ? 460 : 420}
				required
				readonly={disabled}
			/>
		</div>
	</div>
</form>
